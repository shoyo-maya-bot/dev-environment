package com.example.sample.order.batch;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.sample.order.FakeOrderMapper;
import com.example.sample.order.OrderImportService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

/**
 * JOB0001 をどの起動のときに登録するか.
 *
 * <p>後退: {@code @ConditionalOnProperty(app.batch.job=JOB0001)} だけを見ていたため、プロファイル batch を付けずに
 * {@code --app.batch.job=JOB0001} を渡すと、API（Web）として起動したまま取込が走った（終了コードも返らない）。
 */
class OrderImportJobRegistrationTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withBean(FileFetcher.class, () -> loc -> List.of())
            .withBean(OrderImportService.class, () -> new OrderImportService(new FakeOrderMapper()))
            .withUserConfiguration(OrderImportJob.class);

    @Test
    void notRegisteredWithoutBatchProfile() {
        runner.withPropertyValues("app.batch.job=JOB0001")
                .run(ctx -> assertThat(ctx).doesNotHaveBean(OrderImportJob.class));
        runner.withPropertyValues("app.batch.job=JOB0001", "spring.profiles.active=local")
                .run(ctx -> assertThat(ctx).doesNotHaveBean(OrderImportJob.class));
    }

    @Test
    void registeredWithBatchProfileAndJobId() {
        runner.withPropertyValues("app.batch.job=JOB0001", "spring.profiles.active=local,batch")
                .run(ctx -> assertThat(ctx).hasSingleBean(OrderImportJob.class));
    }

    @Test
    void notRegisteredForOtherJobId() {
        runner.withPropertyValues("app.batch.job=JOB9999", "spring.profiles.active=batch")
                .run(ctx -> assertThat(ctx).doesNotHaveBean(OrderImportJob.class));
    }
}
