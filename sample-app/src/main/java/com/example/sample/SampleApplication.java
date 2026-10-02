package com.example.sample;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ConfigurableApplicationContext;

/**
 * サンプルアプリの起動クラス.
 *
 * <p>既定は API（Web サーバー）として起動する。プロファイル batch を付けるとバッチとして起動し、
 * ジョブの終了コードでプロセスを終える。
 */
@SpringBootApplication
public class SampleApplication {

    public static void main(String[] args) {
        ConfigurableApplicationContext ctx = SpringApplication.run(SampleApplication.class, args);
        if (ctx.getEnvironment().matchesProfiles("batch")) {
            System.exit(SpringApplication.exit(ctx));
        }
    }
}
