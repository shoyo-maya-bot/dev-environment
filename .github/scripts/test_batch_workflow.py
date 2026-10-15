"""cloud/modules/batch-workflow の状態機械の定義のテスト（python -m unittest discover -s .github/scripts）.

後退: ジョブフローが ECS タスクの終了を待つだけで、バッチの終了コード（0 正常 / 4 警告 / 8 異常）を見ていなかった.
ecs:runTask.sync は 0 以外の終了を States.TaskFailed にするので、警告（4）まで失敗扱いになり、
逆に結果が成功で返る経路では 8 でも成功扱いになりうる.

後退: RunJob にも状態機械全体にも時間の上限（TimeoutSeconds）が無く、タスクが止まらないと実行が最長 1 年残り、
失敗の通知も出なかった. RunJob の上限（job_timeout_seconds）を超えたら失敗の経路（通知 → JobFailed）へ進むこと.

後退: RunJob（ecs:runTask.sync）を ECS.AmazonECSException で再試行していた. このエラーはタスクの起動前の失敗か、
起動した後（終了を待つ間）の失敗かをエラー名で区別できず、起動後の失敗で再試行すると同じジョブのタスクが 2 つ動く（二重起動）.
RunJob は再試行せず、失敗の経路（通知 → JobFailed）へ進むこと.

定義は terraform console で取り出した JSON（.github/scripts/dump_batch_workflow.sh. AWS にはつながない）を読み、
使っている範囲の States Language を小さく実行して、終了コードごとの行き先を確かめる.
BATCH_WORKFLOW_DEFINITIONS（JSON の置き場所）が無いとき（terraform の無い versions・windows ジョブ）は飛ばす.
CI の terraform ジョブはこれを渡すので、JSON が出来ていなければ失敗になる.
"""

import json
import os
import re
import unittest
from pathlib import Path

DEFS = os.environ.get("BATCH_WORKFLOW_DEFINITIONS")
TOPIC = "arn:aws:sns:ap-northeast-1:123456789012:test-job0001-notification"


def task(exit_code=None, reason=None):
    """ecs:runTask.sync の結果・失敗の Cause に入る、タスクの情報（必要な所だけ）."""
    container = {"Name": "app", "LastStatus": "STOPPED"}
    if exit_code is not None:
        container["ExitCode"] = exit_code
    if reason:
        container["Reason"] = reason
    return {"TaskArn": "arn:aws:ecs:ap-northeast-1:123456789012:task/test/abc", "Containers": [container]}


def get(data, path):
    """$.a.b[0].c の値（無ければ KeyError）."""
    if path == "$":
        return data
    cur = data
    for name, index in re.findall(r"\.([A-Za-z_]\w*)|\[(\d+)\]", path[1:]):
        cur = cur[name] if name else cur[int(index)]
    return cur


def put(data, path, value):
    if path is None:
        return data
    if path == "$":
        return value
    out = json.loads(json.dumps(data))
    keys = path[2:].split(".")
    cur = out
    for k in keys[:-1]:
        cur = cur.setdefault(k, {})
    cur[keys[-1]] = value
    return out


def present(data, path):
    try:
        get(data, path)
        return True
    except (KeyError, IndexError, TypeError):
        return False


def rule_matches(rule, data):
    if "Not" in rule:
        return not rule_matches(rule["Not"], data)
    var = rule["Variable"]
    if "IsPresent" in rule:
        return present(data, var) == rule["IsPresent"]
    value = get(data, var)  # 値が無いと実行時エラー（States.Runtime）. 本物と同じく例外にする
    if "NumericEquals" in rule:
        return isinstance(value, (int, float)) and value == rule["NumericEquals"]
    if "StringMatches" in rule:
        pattern = "".join(".*" if c == "*" else re.escape(c) for c in rule["StringMatches"])
        return isinstance(value, str) and re.fullmatch(pattern, value, re.S) is not None
    raise AssertionError(f"テストが知らない比較: {rule}")


def params(spec, data):
    out = {}
    for k, v in spec.items():
        if not k.endswith(".$"):
            out[k] = v
            continue
        m = re.fullmatch(r"States\.(StringToJson|JsonToString)\((.+)\)", v)
        if m:
            arg = get(data, m.group(2))
            out[k[:-2]] = json.loads(arg) if m.group(1) == "StringToJson" else json.dumps(arg)
        else:
            out[k[:-2]] = get(data, v)
    return out


def run(definition, ecs, sns_fails=False):
    """定義を実行し、（最後の状態名, 通った状態の一覧, 発行した通知）を返す.

    ecs: ("ok", タスクの情報) か ("error", エラー名, Cause（文字列か None））. ecs:runTask.sync の振る舞い.
         ("hang",) はタスクが終わらない. 状態の TimeoutSeconds があれば States.Timeout になり、無ければ終わらない（例外）.
    """
    states = definition["States"]
    name, data, path, published = definition["StartAt"], {"input": 1}, [], []
    for _ in range(50):
        path.append(name)
        st = states[name]
        kind = st["Type"]
        if kind in ("Succeed", "Fail"):
            return name, path, published
        if kind == "Choice":
            name = next((r["Next"] for r in st["Choices"] if rule_matches(r, data)), st.get("Default"))
            continue
        if kind == "Pass":
            src = get(data, st.get("InputPath", "$"))
            result = params(st["Parameters"], src) if "Parameters" in st else src
            data = put(data, st.get("ResultPath", "$"), result)
            name = st["Next"]
            continue
        assert kind == "Task", kind
        if st["Resource"] == "arn:aws:states:::ecs:runTask.sync":
            outcome = ecs
            if ecs[0] == "hang":
                if not st.get("TimeoutSeconds"):
                    raise AssertionError(f"{name} に TimeoutSeconds が無く、終わらないタスクを待ち続ける")
                outcome = ("error", "States.Timeout", None)
        elif st["Resource"] == "arn:aws:states:::sns:publish":
            published.append(params(st["Parameters"], data))
            outcome = ("error", "SNS.AuthorizationErrorException", "denied") if sns_fails else ("ok", {"MessageId": "m"})
        else:
            raise AssertionError(st["Resource"])
        if outcome[0] == "ok":
            data = put(data, st.get("ResultPath", "$"), outcome[1])
            name = st["Next"]
            continue
        err = {"Error": outcome[1]}
        if outcome[2] is not None:
            err["Cause"] = outcome[2]
        catch = next(c for c in st.get("Catch", []) if outcome[1] in c["ErrorEquals"] or "States.ALL" in c["ErrorEquals"])
        data = put(data, catch.get("ResultPath", "$"), err)
        name = catch["Next"]
    raise AssertionError(f"終わらない: {path}")


def failed(exit_code=None, reason=None):
    return ("error", "States.TaskFailed", json.dumps(task(exit_code, reason)))


@unittest.skipUnless(DEFS, "BATCH_WORKFLOW_DEFINITIONS が無い（terraform ジョブで実行）")
class BatchWorkflowTest(unittest.TestCase):
    def load(self, notify):
        p = Path(DEFS or "") / f"definition-notify-{str(notify).lower()}.json"
        self.assertTrue(p.is_file(), f"{p} がありません（dump_batch_workflow.sh を先に実行）")
        return json.loads(p.read_text(encoding="utf-8"))

    def test_structure(self):
        for notify in (False, True):
            d = self.load(notify)
            states = d["States"]
            self.assertIn(d["StartAt"], states)
            nexts = set()
            for st in states.values():
                nexts |= {st.get("Next"), st.get("Default")} - {None}
                nexts |= {c["Next"] for c in st.get("Choices", []) + st.get("Catch", [])}
                if st["Type"] in ("Task", "Pass"):
                    self.assertTrue("Next" in st or st.get("End"), st)
            self.assertLessEqual(nexts, set(states), "存在しない状態への遷移")
            self.assertEqual(set(states) - nexts - {d["StartAt"]}, set(), "どこからも来ない状態")
            has_notify = any(s.get("Resource") == "arn:aws:states:::sns:publish" for s in states.values())
            self.assertEqual(has_notify, notify)

    def test_exit_codes_without_notification(self):
        d = self.load(False)
        cases = {
            "exit 0（結果で返る）": (("ok", task(0)), "Succeeded"),
            "exit 0（念のため失敗でも）": (failed(0), "Succeeded"),
            "exit 4 → 警告で成功扱い": (failed(4), "SucceededWithWarning"),
            "exit 4（結果で返る）": (("ok", task(4)), "SucceededWithWarning"),
            "exit 8 → 失敗": (failed(8), "JobFailed"),
            "exit 8（結果で返っても）": (("ok", task(8)), "JobFailed"),
            "exit 1 → 失敗": (failed(1), "JobFailed"),
            "終了コードが無い（起動前に止まった）": (failed(None, "CannotPullContainerError"), "JobFailed"),
            "Cause が JSON でない": (("error", "States.TaskFailed", "not json"), "JobFailed"),
            "Cause が無い": (("error", "States.TaskFailed", None), "JobFailed"),
            "ECS の起動失敗": (("error", "ECS.AmazonECSException", "capacity"), "JobFailed"),
            "タイムアウト": (("error", "States.Timeout", None), "JobFailed"),
        }
        for label, (ecs, want) in cases.items():
            with self.subTest(label):
                end, path, published = run(d, ecs)
                self.assertEqual(end, want, path)
                self.assertEqual(published, [])
        self.assertEqual(d["States"]["JobFailed"]["Type"], "Fail")
        self.assertEqual(d["States"]["SucceededWithWarning"]["Type"], "Succeed")

    def test_notification(self):
        d = self.load(True)
        for ecs, want, subject in (
            (("ok", task(0)), "Succeeded", None),
            (failed(4), "SucceededWithWarning", "WARNING"),
            (failed(8), "JobFailed", "FAILED"),
            (("error", "ECS.AmazonECSException", "x"), "JobFailed", "FAILED"),
        ):
            with self.subTest(want=want, subject=subject):
                end, path, published = run(d, ecs)
                self.assertEqual(end, want, path)
                if subject is None:
                    self.assertEqual(published, [])
                else:
                    self.assertEqual(len(published), 1)
                    self.assertEqual(published[0]["TopicArn"], TOPIC)
                    self.assertIn(subject, published[0]["Subject"])
                    self.assertIn("ExitCode" if ecs[0] == "ok" or ecs[1] == "States.TaskFailed" else "Error",
                                  published[0]["Message"])  # 調べるための情報（終了コード・エラー）が本文にある
        # 通知に失敗しても、ジョブの結果は変えない
        self.assertEqual(run(d, failed(4), sns_fails=True)[0], "SucceededWithWarning")
        self.assertEqual(run(d, failed(8), sns_fails=True)[0], "JobFailed")


    def test_timeouts(self):
        for notify in (False, True):
            with self.subTest(notify=notify):
                d = self.load(notify)
                states = d["States"]
                run_job = states["RunJob"]
                self.assertEqual(run_job["TimeoutSeconds"], 3600)  # job_timeout_seconds の既定
                # 全体の上限は、RunJob の上限・起動の再試行の待ち・通知の上限の合計より長い（RunJob の時間切れが先に来て、失敗の経路を通る）
                retry_wait = sum(r["IntervalSeconds"] * r["BackoffRate"] ** i
                                 for r in run_job.get("Retry", []) for i in range(r["MaxAttempts"]))
                notify_max = max((s.get("TimeoutSeconds", 0) for s in states.values()
                                  if s.get("Resource") == "arn:aws:states:::sns:publish"), default=0)
                self.assertIsInstance(d.get("TimeoutSeconds"), int)
                self.assertGreater(d["TimeoutSeconds"], run_job["TimeoutSeconds"] + retry_wait + notify_max)
                # 外部を呼ぶ Task はすべて上限を持つ
                for name, st in states.items():
                    if st["Type"] == "Task":
                        self.assertGreater(st.get("TimeoutSeconds", 0), 0, name)
                # 時間切れ → 失敗（通知ありなら FAILED を通知してから）
                end, path, published = run(d, ("hang",))
                self.assertEqual(end, "JobFailed", path)
                if notify:
                    self.assertEqual(len(published), 1)
                    self.assertIn("FAILED", published[0]["Subject"])
                    self.assertIn("States.Timeout", published[0]["Message"])
                else:
                    self.assertEqual(published, [])

    def test_run_job_is_not_retried(self):
        """ECS のエラーで RunJob をやり直さない（起動後の失敗でのやり直しは二重起動になる）."""
        for notify in (False, True):
            with self.subTest(notify=notify):
                d = self.load(notify)
                run_job = d["States"]["RunJob"]
                self.assertEqual(run_job.get("Retry", []), [], "RunJob に Retry があります（二重起動のおそれ）")
                # 起動後の失敗に当たるエラーは、そのまま失敗の経路へ（RunJob を 1 回だけ通る）
                for err in ("ECS.AmazonECSException", "States.TaskFailed", "States.Timeout"):
                    end, path, _ = run(d, ("error", err, None))
                    self.assertEqual(end, "JobFailed", path)
                    self.assertEqual(path.count("RunJob"), 1, path)

    def test_timeout_variable(self):
        p = Path(DEFS or "") / "definition-timeout-120.json"
        self.assertTrue(p.is_file(), f"{p} がありません（dump_batch_workflow.sh を先に実行）")
        d = json.loads(p.read_text(encoding="utf-8"))
        self.assertEqual(d["States"]["RunJob"]["TimeoutSeconds"], 120)
        default = self.load(False)
        # 全体の上限も変数に追随する（差は RunJob の上限の差だけ）
        self.assertEqual(default["TimeoutSeconds"] - d["TimeoutSeconds"], 3600 - 120)
        self.assertEqual(run(d, ("hang",))[0], "JobFailed")


class InterpreterTest(unittest.TestCase):
    """テスト用の小さな実行器そのもの（terraform が無くても動く）."""

    def test_get_and_present(self):
        data = {"task": task(4)}
        self.assertEqual(get(data, "$.task.Containers[0].ExitCode"), 4)
        self.assertFalse(present({"task": task()}, "$.task.Containers[0].ExitCode"))
        with self.assertRaises(KeyError):
            rule_matches({"Variable": "$.error.Cause", "StringMatches": "{*"}, {"error": {}})

    def test_hang_without_timeout_never_ends(self):
        d = {"StartAt": "R", "States": {"R": {"Type": "Task", "Resource": "arn:aws:states:::ecs:runTask.sync", "End": True}}}
        with self.assertRaisesRegex(AssertionError, "TimeoutSeconds"):
            run(d, ("hang",))

    def test_string_to_json(self):
        out = params({"value.$": "States.StringToJson($.c)"}, {"c": '{"a": 1}'})
        self.assertEqual(out, {"value": {"a": 1}})


if __name__ == "__main__":
    unittest.main()
