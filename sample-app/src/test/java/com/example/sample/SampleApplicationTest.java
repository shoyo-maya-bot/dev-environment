package com.example.sample;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** 起動クラスの、起動前のバッチ判定と起動失敗時の終了コード. */
class SampleApplicationTest {

    @Test
    void バッチの起動失敗はREADMEの決まりどおり終了コード8() {
        // 後退: 起動時の失敗（DB につながらない等）は JVM の既定の 1 で終わり、README の 8（異常）と合わなかった
        assertThat(SampleApplication.startupFailureExitCode()).isEqualTo(8);
    }

    @Test
    void 環境変数のプロファイルにbatchがあればバッチ() {
        assertThat(SampleApplication.batchRequested(new String[0], null, "cloud,batch")).isTrue();
        assertThat(SampleApplication.batchRequested(new String[0], null, " cloud , batch ")).isTrue();
        assertThat(SampleApplication.batchRequested(new String[0], null, "cloud")).isFalse();
        assertThat(SampleApplication.batchRequested(new String[0], null, "batchx")).isFalse();
        assertThat(SampleApplication.batchRequested(new String[0], null, null)).isFalse();
    }

    @Test
    void 引数とシステムプロパティは環境変数より優先する() {
        String[] args = {"--app.batch.job=JOB0001", "--spring.profiles.active=local,batch"};
        assertThat(SampleApplication.batchRequested(args, null, "cloud")).isTrue();
        assertThat(SampleApplication.batchRequested(new String[] {"--spring.profiles.active=local"}, null, "batch")).isFalse();
        assertThat(SampleApplication.batchRequested(new String[0], "batch", "cloud")).isTrue();
        assertThat(SampleApplication.batchRequested(new String[0], "cloud", "batch")).isFalse();
    }
}
