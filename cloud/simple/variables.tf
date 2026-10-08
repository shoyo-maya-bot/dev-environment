variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "system_name" {
  type    = string
  default = "sample-proto"
}

variable "allowed_http_cidrs" {
  description = "Web 画面（Nginx 80 番）へ接続を許可する IP 範囲（社内の出口 IP など。IPv4 の CIDR 形式、例: 203.0.113.10/32）。インターネット全体（0.0.0.0/0）は指定できない"
  type        = list(string)

  validation {
    condition     = length(var.allowed_http_cidrs) > 0
    error_message = "allowed_http_cidrs に、接続を許可する IP 範囲を 1 つ以上指定してください（例: [\"203.0.113.10/32\"]）。"
  }

  # CIDR 形式（アドレス/プレフィックス長）で、ネットワークアドレスに揃っていること（203.0.113.10/24 のような書き間違いも弾く）.
  # 取り込み先は cidr_ipv4 なので IPv4 だけ
  validation {
    condition = alltrue([
      for c in var.allowed_http_cidrs :
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", c)) && can(cidrhost(c, 0)) && try(cidrhost(c, 0) == split("/", c)[0], false)
    ])
    error_message = "allowed_http_cidrs は IPv4 の CIDR 形式（例: 203.0.113.10/32、198.51.100.0/24）で、ホスト部を 0 にして指定してください。"
  }

  # インターネット全体への公開を拒否する（0.0.0.0/0・::/0 と、それに等しい /0 の範囲）
  validation {
    condition = alltrue([
      for c in var.allowed_http_cidrs : !contains(["0.0.0.0/0", "::/0"], trimspace(c)) && !endswith(trimspace(c), "/0")
    ])
    error_message = "allowed_http_cidrs にインターネット全体（0.0.0.0/0・::/0）は指定できません。社内の出口 IP など、必要な範囲だけを指定してください。"
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
