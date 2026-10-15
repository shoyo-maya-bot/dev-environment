-- アプリ用の DB ユーザー（API・バッチが接続に使う）を作る SQL の例. cloud/README.md の「アプリ用の DB ユーザー」.
--
-- マスターユーザーは何でもできる（テーブルの削除・ユーザーの作成など）ので、アプリには使わず、
-- 業務データの読み書きだけができるユーザーを作る. テーブルの作成・変更・削除（スキーマの変更）はマスターユーザーか、
-- マイグレーション用のユーザーで行う.
--
-- 使い方: CloudShell の VPC 環境から、マスターユーザーで sampledb に接続し（01_schema.sql を流すときと同じ）、
--   このファイルの中身を貼り付けて実行する（VPC 環境ではファイルをアップロードできない）. パスワードは \prompt で聞かれたときに貼り付ける
--   （SQL の履歴・ファイルに残さない）. 同じパスワードを、後で Secrets Manager のシークレットにも入れる.
-- ユーザー名 sample_app は例. 変えるときは下の sample_app をすべて変える.

\prompt 'アプリ用ユーザー sample_app のパスワード: ' app_password
CREATE ROLE sample_app LOGIN PASSWORD :'app_password';

-- 接続とスキーマの利用だけ. public スキーマにテーブルは作れない（PostgreSQL 15 以降の既定. 念のため明示する）
GRANT CONNECT ON DATABASE sampledb TO sample_app;
GRANT USAGE ON SCHEMA public TO sample_app;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- 業務データの読み書き（sample-app は SELECT と INSERT だけを使う. 更新・削除が要るジョブを足したら付け足す）
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO sample_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO sample_app;

-- この後マスターユーザーが作るテーブル・シーケンスにも同じ権限を付ける
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT ON TABLES TO sample_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO sample_app;
