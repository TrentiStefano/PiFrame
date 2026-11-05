$msg = Get-Content "C:\Users\User\git_status_check.txt" -ErrorAction SilentlyContinue
[System.Windows.Forms.MessageBox]::Show("STATUS: $msg", "Git Check")
