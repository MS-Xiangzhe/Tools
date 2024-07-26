$VMList = @(
    @{ResourceGroup = "GENDOX_LABS"; VMName = "interoptoolsppe"; TaskNamesToCheck = @() ; TaskPathsToCheck = @() ; ProcessNamesToCheck = @() }
    @{ResourceGroup = "GENDOX_LABS"; VMName = "GenDoxDM3"; TaskNamesToCheck = @() ; TaskPathsToCheck = @("\\DMtest", "\\PATSetup") ; ProcessNamesToCheck = @() }
    @{ResourceGroup = "GENDOX_LABS"; VMName = "GenDoxServiceTest"; TaskNamesToCheck = @() ; TaskPathsToCheck = @("\\Microsoft\\OInterop", "\\Microsoft\\OInteropSA") ; ProcessNamesToCheck = @() }
    #@{ResourceGroup = "GENDOX_LABS"; VMName = "interopservices"; TaskNamesToCheck = @() ; TaskPathsToCheck = @() }
    #@{ResourceGroup = "GENDOX_LABS"; VMName = "GenDoxServices3"; TaskNamesToCheck = @() ; TaskPathsToCheck = @("\\Interoperability Tasks", "\\PATSetup") }
    #@{ResourceGroup = "GENDOX_LABS"; VMName = "GendoxDM4"; TaskNamesToCheck = @() ; TaskPathsToCheck = @("\\DistillMetaData", "\\PATSetup") }
)


# Ensures you do not inherit an AzContext in your runbook
$null = Disable-AzContextAutosave -Scope Process

# Connect using a Managed Service Identity
try {
    $AzureConnection = (Connect-AzAccount -SubscriptionId 963c56be-5368-4fd1-9477-f7d214f9888a).context
}
catch {
    Write-Output "There is no system-assigned user identity. Aborting." 
    exit
}

# set and store context
$AzureContext = Set-AzContext -SubscriptionName "GenDox Document Management Service" -DefaultProfile $AzureConnection

$scriptBlock = {
    function Write-VMLog {
        param (
            [string]$ResourceGroup,
            [string]$VMName,
            [string]$Message
        )
        Write-Host "$ResourceGroup::${VMName}: $Message"
    }

    $scriptPath = "C:\temp\update_windows.ps1"
    function UpdateWindows {
        param (
            [string]$ResourceGroup,
            [string]$VMName,
            [string[]]$TaskNamesToCheck,
            [string[]]$TaskPathsToCheck,
            [string[]]$ProcessNamesToCheck
        )
        Write-VMLog $ResourceGroup $VMName "Script downloading..."
        $executionResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/MS-Xiangzhe/Tools/main/update_windows.ps1' -OutFile `"$scriptPath`""
        if ($executionResult.Status -ne "Succeeded") {
            Write-VMLog $ResourceGroup $VMName "Script download failed."
            return $executionResult
        }
        Write-VMLog $ResourceGroup $VMName "Script downloaded."
        Write-VMLog $ResourceGroup $VMName "Script execution..."
        $ArgsTaskNamesToCheck = ($TaskNamesToCheck -join ',').TrimEnd(',')
        $ArgsTaskPathsToCheck = ($TaskPathsToCheck -join ',').TrimEnd(',')
        $ArgsProcessNamesToCheck = ($ProcessNamesToCheck -join ',').TrimEnd(',')
        $executionResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "powershell -ExecutionPolicy Unrestricted -File `"$scriptPath`" `"$ArgsTaskNamesToCheck`" `"$ArgsTaskPathsToCheck`" `"$ArgsProcessNamesToCheck`""
        Write-VMLog $ResourceGroup $VMName "Script executed."
        $executionResultJson = $executionResult | ConvertTo-Json -Depth 10
        Write-VMLog $ResourceGroup $VMName $executionResultJson
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
            Write-VMLog $ResourceGroup $VMName "Stoping VM: $VMName in Resource Group: $ResourceGroup"
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
            Write-VMLog $ResourceGroup $VMName "Starting VM: $VMName in Resource Group: $ResourceGroup"
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
            Write-VMLog $ResourceGroup $VMName "VM is not running. Starting the VM."
            StartAzVM -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
        }
    }

    function Get-AzVMStatus {
        param (
            [string]$ResourceGroup,
            [string]$VMName
        )
        Write-VMLog $ResourceGroup $VMName "Getting VM status..."
        $status = (Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -DefaultProfile $AzureContext).Statuses[1].Code
        Write-VMLog $ResourceGroup $VMName "VM status: $status"
        if ($status -eq "Powerstate/running") {
            try {
                Write-VMLog $ResourceGroup $VMName "VM is running. Checking if it is accessible."
                $maxLoop = 3
                while ($maxLoop -gt 0) {
                    $maxLoop--
                    $status = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "Write-VMLog $ResourceGroup $VMName 'VM is running.'"
                    if ($status.Status -ne "Succeeded") {
                        Write-VMLog $ResourceGroup $VMName "VM is not accessible."
                        return $false
                    }
                    else {
                        Start-Sleep -Seconds 10
                    }
                }
            }
            catch {
                Write-VMLog $ResourceGroup $VMName "VM is not accessible."
                return $false
            }
            Write-VMLog $ResourceGroup $VMName "VM is accessible."
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
        Write-VMLog $ResourceGroup $VMName "Updating Windows for VM: $VMName in Resource Group: $ResourceGroup"
        $maxLoop = 3
        while ($maxLoop -gt 0) {
            Write-VMLog $ResourceGroup $VMName "RestartVMIfNeeded... Checking if VM is running."
            if ((Get-AzVMStatus -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext) -ne $true) {
                Write-VMLog $ResourceGroup $VMName "RestartVMIfNeeded..."
                RestartVMIfNeeded -ResourceGroup $ResourceGroup -VMName $VMName -AzureContext $AzureContext
            }
            Write-VMLog $ResourceGroup $VMName "RestartVMIfNeeded executed."
            Write-VMLog $ResourceGroup $VMName "UpdateWindows..."
            $executionResult = UpdateWindows -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
            Write-VMLog $ResourceGroup $VMName "UpdateWindows executed."
            if ((CheckForUpdates -executionResult $executionResult) -eq $false) {
                Write-VMLog $ResourceGroup $VMName "No Update available."
                break
            }
            $maxLoop--
        }
        if ($maxLoop -eq 0) {
            Write-VMLog $ResourceGroup $VMName "Max loop reached. Exiting the script."
        }
    }
}
$scriptBlockString = $scriptBlock.ToString()

Write-Host "Script executing..."

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "PowerShell version is less than 7.0. Parallel processing is not supported."
    # Alternative approach without parallel processing
    $VMList | ForEach-Object {
        $scriptBlockFromString = [scriptblock]::Create($scriptBlockString)
        New-Module -ScriptBlock $scriptBlockFromString -Name MyCustomModule | Import-Module
        $ResourceGroup = $_.ResourceGroup
        $VMName = $_.VMName
        $TaskNamesToCheck = $_.TaskNamesToCheck
        $TaskPathsToCheck = $_.TaskPathsToCheck

        Write-Host "Updating Windows for VM: $VMName in Resource Group: $ResourceGroup"
        Write-Host "Task Scheduled check: names: $TaskNamesToCheck, paths: $TaskPathsToCheck"
        ManageVMUpdates -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
        Write-Host "UpdateWindows executed."
    }
}
else {
    $VMList | ForEach-Object -Parallel {
        # https://stackoverflow.com/a/61273544
        # https://stackoverflow.com/a/77054556
        # https://superuser.com/questions/1767655/how-to-import-a-module-in-powershell-from-a-string-variable
        $scriptBlockFromString = [scriptblock]::Create($using:scriptBlockString)
        New-Module -ScriptBlock $scriptBlockFromString -Name MyCustomModule | Import-Module
        $ResourceGroup = $_.ResourceGroup
        $VMName = $_.VMName
        $TaskNamesToCheck = $_.TaskNamesToCheck
        $TaskPathsToCheck = $_.TaskPathsToCheck

        Write-Host "Updating Windows for VM: $VMName in Resource Group: $ResourceGroup"
        Write-Host "Task Scheduled check: names: $TaskNamesToCheck, paths: $TaskPathsToCheck"
        ManageVMUpdates -ResourceGroup $ResourceGroup -VMName $VMName -TaskNamesToCheck $TaskNamesToCheck -TaskPathsToCheck $TaskPathsToCheck
        Write-Host "UpdateWindows executed."
    } -ThrottleLimit 5
}

Write-Host "Script executed."