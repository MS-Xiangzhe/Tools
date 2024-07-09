$ResourceGroup = "GENDOX_LABS"
$VMName = "interoptoolsppe"

# Ensures you do not inherit an AzContext in your runbook
$null = Disable-AzContextAutosave -Scope Process

# Connect using a Managed Service Identity
try {
    $AzureConnection = (connect-azaccount -SubscriptionId 963c56be-5368-4fd1-9477-f7d214f9888a).context
}
catch {
    Write-Host "There is no system-assigned user identity. Aborting." 
    exit
}

# set and store context
$AzureContext = Set-AzContext -SubscriptionName "GenDox Document Management Service" -DefaultProfile $AzureConnection

# Get current state of VM
$status = (Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -DefaultProfile $AzureContext).Statuses[1].Code
Write-Host "`r`n Beginning VM status: $status `r`n"

function DownloadAndExecuteScript {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [string]$scriptPath
    )
    Write-Host "`r`n Script downloading... `r`n"
    $executionResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/MS-Xiangzhe/Tools/main/update_windows.ps1' -OutFile `"$scriptPath`""
    Write-Host "`r`n Script downloaded. `r`n"
    $executionResultJson = $executionResult | ConvertTo-Json -Depth 10
    Write-Host $executionResultJson
    Write-Host "`r`n Script execution... `r`n"
    $executionResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "powershell -ExecutionPolicy Unrestricted -File `"$scriptPath`""
    Write-Host "`r`n Script executed. `r`n"
    $executionResultJson = $executionResult | ConvertTo-Json -Depth 10
    Write-Host $executionResultJson
    return $executionResult
}
function CheckForUpdates {
    param (
        [object]$executionResult
    )
    if ($executionResult.Value[0].Message -match "No update available") {
        return $false
    }
    else {
        return $true
    }
}

function RestartVMIfNeeded {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [object]$AzureContext
    )
    $status = (Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -DefaultProfile $AzureContext).Statuses[1].Code
    if ($status -eq "Powerstate/running") {
        Stop-AzVM -Name $VMName -ResourceGroupName $ResourceGroup -DefaultProfile $AzureContext -Force
        Start-Sleep -Seconds 10
    }
    Start-AzVM -Name $VMName -ResourceGroupName $ResourceGroup -DefaultProfile $AzureContext
}

$scriptPath = "C:\temp\update_windows.ps1"

# 第一次下载并执行脚本
$executionResult = DownloadAndExecuteScript -ResourceGroup $ResourceGroup -VMName $VMName -scriptPath $scriptPath
Write-Host $executionResult

# 检查是否有更新
if (CheckForUpdates -executionResult $executionResult) {
    # 如果有更新，重启虚拟机
    RestartVMIfNeeded -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
    # 再次下载并执行脚本
    $executionResult = DownloadAndExecuteScript -ResourceGroup $ResourceGroup -VMName $VMName -scriptPath $scriptPath
    Write-Host $executionResult
    # 再次检查更新并可能重启
    if (CheckForUpdates -executionResult $executionResult) {
        RestartVMIfNeeded -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
    }
}
Write-Host "`r`n Script execution completed. `r`n"