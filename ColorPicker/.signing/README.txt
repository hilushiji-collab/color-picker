自签名代码签名证书（让重新编译后系统授权依然有效，无需重新授权）

钥匙串身份名: Qusheqi Code Signing
p12 密码:      （私下保存，勿写入仓库；下方命令里的 <密码> 自行替换）

注意：qusheqi.p12 是私钥，已加入 .gitignore，不随仓库上传。换机时另行私密传输。

== 万一这台机器的钥匙串里没有这个身份了（如换机/被清），重新导入：==
  security import qusheqi.p12 -k ~/Library/Keychains/login.keychain-db -P <密码> -A
然后 bash build.sh 即可。第一次导入新身份后，屏幕录制/辅助功能需再授权一次，之后永久有效。

== 确认身份是否存在： ==
  security find-identity -p codesigning      # 应能看到 "Qusheqi Code Signing"
