$scriptPath = "C:\temp\update_windows.ps1"

$VMList = @(
   # @{ResourceGroup="GENDOX_LABS"; VMName="interoptoolsppe"; TaskNamesToCheck=@() ; TaskPathsToCheck=@()}
   # @{ResourceGroup="GENDOX_LABS"; VMName="interopservices"; TaskNamesToCheck=@() ; TaskPathsToCheck=@()}
   # @{ResourceGroup="GENDOX_LABS"; VMName="GenDoxServices3"; TaskNamesToCheck=@() ; TaskPathsToCheck=@("\\Interoperability Tasks", "\\PATSetup")}
   # @{ResourceGroup="GENDOX_LABS"; VMName="GendoxDM4"; TaskNamesToCheck=@() ; TaskPathsToCheck=@("\\DistillMetaData", "\\PATSetup")}
    @{ResourceGroup="GENDOX_LABS"; VMName="GenDoxDM3"; TaskNamesToCheck=@() ; TaskPathsToCheck=@("\\DMtest", "\\PATSetup")}
   # @{ResourceGroup="GENDOX_LABS"; VMName="GenDoxServiceTest"; TaskNamesToCheck=@() ; TaskPathsToCheck=@("\\Microsoft\\OInterop", "\\Microsoft\\OInteropSA")}
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
    if ($executionResult.Status -ne "Succeeded") {
        Write-Host "Script download failed."
        return $executionResult
    }
    Write-Host "Script downloaded."
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
    if ($executionResult.Value[0].Message -match "No reboot is pending") {
        return $false
    }
    else {
        return $true
    }
}

function StopAzVM {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [object]$AzureContext
    )
    do {
        Write-Host "Stoping VM: $VMName in Resource Group: $ResourceGroup"
        Stop-AzVM -Name $VMName -ResourceGroupName $ResourceGroup -Force -DefaultProfile $AzureContext
    } while ((Get-AzVMStatus -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext) -ne $false)
}

function StartAzVM {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [object]$AzureContext
    )
    while ((Get-AzVMStatus -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext) -ne $true) {
        Write-Host "Starting VM: $VMName in Resource Group: $ResourceGroup"
        Start-AzVM -Name $VMName -ResourceGroupName $ResourceGroup -DefaultProfile $AzureContext
        Start-Sleep -Seconds 10
    }
}

function RestartVMIfNeeded {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [object]$AzureContext
    )
    while ((Get-AzVMStatus -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext) -ne $true) {
        StopAzVM -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
        Write-Host "VM is not running. Starting the VM."
        StartAzVM -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
    }
}

function Get-AzVMStatus {
    param (
        [string]$ResourceGroup,
        [string]$VMName
    )
    Write-Host "Getting VM status..."
    $status = (Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -DefaultProfile $AzureContext).Statuses[1].Code
    Write-Host "VM status: $status"
    if ($status -eq "Powerstate/running") {
        try{
            Write-Host "VM is running. Checking if it is accessible."
            $maxLoop = 3
            while ($maxLoop -gt 0) {
                $maxLoop--
                $status = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "Write-Host 'VM is running.'"
                if ($status.Status -ne "Succeeded") {
                    Write-Host "VM is not accessible."
                    return $false
                } else {
                    Start-Sleep -Seconds 10
                }
            }
        } catch {
            Write-Host "VM is not accessible."
            return $false
        }
        Write-Host "VM is accessible."
        return $true
    }
    return $false
}

function ManageVMUpdates {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [string]$TaskNamesToCheck,
        [string]$TaskPathsToCheck 
    )

    # Get current state of VM
    Write-Host "Updating Windows for VM: $VMName in Resource Group: $ResourceGroup"
    $maxLoop = 3
    while ($maxLoop -gt 0) {
        Write-Host "RestartVMIfNeeded... Checking if VM is running."
        if ((Get-AzVMStatus -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext) -ne $true) {
            Write-Host "RestartVMIfNeeded..."
            RestartVMIfNeeded -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
        }
        Write-Host "RestartVMIfNeeded executed."
        Write-Host "UpdateWindows..."
        UpdateWindows -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
        Write-Host "UpdateWindows executed."
        if (CheckForUpdates -executionResult $executionResult -eq $false) {
            Write-Host "No Update available."
            break
        }
        $maxLoop--
    }
    if ($maxLoop -eq 0) {
        Write-Host "Max loop reached. Exiting the script."
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
    ManageVMUpdates -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
    Write-Host "UpdateWindows executed."
}

Write-Host "Script executed."