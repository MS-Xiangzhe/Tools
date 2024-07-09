$scriptPath = "C:\temp\update_windows.ps1"

$VMList = @(
    @{ResourceGroup="GENDOX_LABS"; VMName="interoptoolsppe"; TaskNamesToCheck=@() ; TaskPathsToCheck=@()}
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
        [string[]]$TaskNamesToCheck,
        [string[]]$TaskPathsToCheck
    )
    Write-Host "Script downloading..."
    $executionResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/MS-Xiangzhe/Tools/main/update_windows.ps1' -OutFile `"$scriptPath`""
    Write-Host "Script downloaded."
    $executionResultJson = $executionResult | ConvertTo-Json -Depth 10
    Write-Host $executionResultJson
    Write-Host "Script execution..."
    $ArgsTaskNamesToCheck = ($TaskNamesToCheck -join ',').TrimEnd(',')
    $ArgsTaskPathsToCheck = ($TaskPathsToCheck -join ',').TrimEnd(',')
    $executionResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "powershell -ExecutionPolicy Unrestricted -File `"$scriptPath`" `"$ArgsTaskNamesToCheck`" `"$ArgsTaskPathsToCheck`""
    Write-Host "Script executed."
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
    Write-Host "Getting VM status..."
    $status = (Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -DefaultProfile $AzureContext).Statuses[1].Code
    Write-Host "Beginning VM status: $status"
    Write-Host "Updating Windows for VM: $VMName in Resource Group: $ResourceGroup"
    UpdateWindows -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
    $maxLoop = 3
    while ($true) {
        Write-Host "UpdateWindows..."
        $executionResult = UpdateWindows -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
        Write-Host "UpdateWindows executed."
        Write-Host "RestartVMIfNeeded..."
        RestartVMIfNeeded -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
        Write-Host "RestartVMIfNeeded executed."
        if (!CheckForUpdates -executionResult $executionResult) {
            Write-Host "No Update available."
            break
        }
        Write-Host "Update available. Checking again."
        $maxLoop--
        if ($maxLoop -eq 0) {
            Write-Host "Max loop reached. Exiting the script."
            break
        }
    }
}

Write-Host "Script executing..."
foreach ($vm in $VMList) {
    $ResourceGroup = $vm.ResourceGroup
    $VMName = $vm.VMName
    $TaskNamesToCheck = $vm.TaskNamesToCheck
    $TaskPathsToCheck = $vm.TaskPathsToCheck

    Write-Host "Updating Windows for VM: $VMName in Resource Group: $ResourceGroup"
    Write-Host "Task Scheduled check: names: $TaskNamesToCheck, paths: $TaskPathsToCheck"
    UpdateWindows -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
    Write-Host "UpdateWindows executed."
}

Write-Host "Script executed."