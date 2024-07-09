$scriptPath = "C:\temp\update_windows.ps1"

$VMList = @(
    ("GENDOX_LABS", "interoptoolsppe", "", "")
)


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


function UpdateWindows {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [string]$TaskNamesToCheck,
        [string]$TaskPathsToCheck 
    )
    Write-Host "`r`n Script downloading... `r`n"
    $executionResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/MS-Xiangzhe/Tools/main/update_windows.ps1' -OutFile `"$scriptPath`""
    Write-Host "`r`n Script downloaded. `r`n"
    $executionResultJson = $executionResult | ConvertTo-Json -Depth 10
    Write-Host $executionResultJson
    Write-Host "`r`n Script execution... `r`n"
    $executionResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "powershell -ExecutionPolicy Unrestricted -File `"$scriptPath`" -TaskNamesToCheck `"$TaskNamesToCheck`" -TaskPathsToCheck `"$TaskPathsToCheck`""
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

function ManageVMUpdates {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [string]$TaskNamesToCheck,
        [string]$TaskPathsToCheck 
    )

    # Get current state of VM
    $status = (Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -DefaultProfile $AzureContext).Statuses[1].Code
    Write-Host "`r`n Beginning VM status: $status `r`n"

    $scriptPath = "C:\temp\update_windows.ps1"

    $maxLoop = 3
    foreach ($vm in $VMList) {
        $ResourceGroup = $vm[0]
        $VMName = $vm[1]
        # 假设 TaskNamesToCheck 和 TaskPathsToCheck 已经定义
        $TaskNamesToCheck = "您的任务名称"
        $TaskPathsToCheck = "您的任务路径"

        Write-Host "Updating Windows for VM: $VMName in Resource Group: $ResourceGroup"
        UpdateWindows -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
    }
    while ($true) {
        Write-Host "`r`n UpdateWindows... `r`n"
        $executionResult = UpdateWindows -ResourceGroup $ResourceGroup -VMName $VMName -scriptPath $scriptPath -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
        Write-Host "`r`n UpdateWindows executed. `r`n"
        Write-Host "`r`n RestartVMIfNeeded... `r`n"
        RestartVMIfNeeded -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
        Write-Host "`r`n RestartVMIfNeeded executed. `r`n"
        if (!CheckForUpdates -executionResult $executionResult) {
            Write-Host "No Update available."
            break
        }
        Write-Host "`r`n Update available. Checking again. `r`n"
        $maxLoop--
        if ($maxLoop -eq 0) {
            Write-Host "Max loop reached. Exiting the script."
            break
        }
    }
}

Write-Host "Script executing..."
foreach ($vm in $VMList) {
    $ResourceGroup = $vm[0]
    $VMName = $vm[1]
    $TaskNamesToCheck = $vm[2]
    $TaskPathsToCheck = $vm[3]

    Write-Host "Updating Windows for VM: $VMName in Resource Group: $ResourceGroup"
    UpdateWindows -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
    Write-Host "UpdateWindows executed."
}

Write-Host "Script executed."