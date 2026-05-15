# 设置Git全局配置
Write-Host "Setting Git global configuration..."
git config --global user.name "Zhao Yi"
git config --global user.email "717880671@qq.com"

# 验证配置是否正确
Write-Host "\nVerifying Git configuration..."
git config --global user.name
git config --global user.email

# 设置当前仓库的配置
Write-Host "\nSetting local repository configuration..."
git config user.name "Zhao Yi"
git config user.email "717880671@qq.com"

# 验证本地配置
Write-Host "\nVerifying local repository configuration..."
git config user.name
git config user.email

Write-Host "\nGit configuration fixed!"
