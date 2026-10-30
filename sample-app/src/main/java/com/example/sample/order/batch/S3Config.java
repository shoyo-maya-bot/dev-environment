package com.example.sample.order.batch;

import java.net.URI;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3ClientBuilder;

/**
 * S3 クライアント.
 *
 * <p>app.s3.endpoint を指定したとき（ローカル）はエミュレータへ接続する。
 * 未指定（クラウド）は IAM ロール等の標準の認証情報を使う。
 *
 * <p>リージョンは app.s3.region（環境変数 APP_S3_REGION。cloud/environments の Terraform が var.region を渡す）→
 * 環境変数 AWS_REGION → ap-northeast-1 の順に決める。
 */
@Configuration
public class S3Config {

    @Bean
    public S3Client s3Client(
            @Value("${app.s3.region:${AWS_REGION:ap-northeast-1}}") String region,
            @Value("${app.s3.endpoint:}") String endpoint,
            @Value("${app.s3.access-key:test}") String accessKey,
            @Value("${app.s3.secret-key:test}") String secretKey) {
        S3ClientBuilder b = S3Client.builder().region(Region.of(region));
        if (endpoint.isBlank()) {
            b.credentialsProvider(DefaultCredentialsProvider.builder().build());
        } else {
            b.endpointOverride(URI.create(endpoint))
                    .forcePathStyle(true)
                    .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKey, secretKey)));
        }
        return b.build();
    }
}
