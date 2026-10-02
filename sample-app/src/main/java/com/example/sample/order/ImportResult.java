package com.example.sample.order;

import java.util.List;

/**
 * 取込結果.
 *
 * @param imported 登録した件数
 * @param duplicated 登録済みのため飛ばした件数
 * @param errors 形式エラーで飛ばした行（"行番号: 理由"）
 */
public record ImportResult(int imported, int duplicated, List<String> errors) {

    public boolean hasErrors() {
        return !errors.isEmpty();
    }
}
