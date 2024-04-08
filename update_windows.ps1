param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = "localhost",

    [Parameter(Mandatory = $false)]
    [string]$AzResourceGroupName = "DefaultResourceGroup",

    [Parameter(Mandatory = $false)]
    [string]$AzName = "DefaultVirtualMachine",

    [Parameter(Mandatory = $false)]
    [string]$Taskpath = "/*",

    [Parameter(Mandatory = $false)]
    [switch]$DisableUpdateModule = $false
)

function InstallAndUpdateModules {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModuleNames,

        [Parameter(Mandatory = $false)]
        [bool]$DisableUpdate = $false
    )

    foreach ($ModuleName in $ModuleNames) {
        # Check if module is installed
        if (-not(Get-Module -ListAvailable -Name $ModuleName)) {
            # If not installed, install for the current user
            Write-Host "Installing module $ModuleName"
            Install-Module -Name $ModuleName -Scope CurrentUser -Force
        }

        # Update the module
        if (-not $DisableUpdate) {
            Write-Host "Updating module $ModuleName"
            Update-Module -Name $ModuleName -Force
        }

        # Import the module
        Import-Module $ModuleName
    }
}

Write-Host "Prepare powershell modules"
# Call the function with the module names
InstallAndUpdateModules -ModuleNames @('PSWindowsUpdate', 'PendingReboot', 'AzureRM') -DisableUpdate $DisableUpdateModule


# Loop until no tasks are running
while ($true) {
    # Check if any task is running
    $runningTasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Running' }

    if ($runningTasks) {
        Write-Host "There are running tasks. Waiting 10 seconds before checking again."
        Start-Sleep -Seconds 10
    } else {
        Write-Host "No tasks are running. Continuing with the script."
        break
    }
}

# Rest of your script...
Write-Host "Check Windows Update for $ComputerName"
# Rest of your script...
Get-WindowsUpdate -ComputerName $ComputerName -Verbose
Install-WindowsUpdate -ComputerName $ComputerName -AcceptAll -AutoReboot -Verbose

# check reboot pending
Test-PendingReboot -ComputerName $ComputerName -Detailed

# Ask user to shutdown
$response = Read-Host -Prompt "Shutdown $ComputerName? (Y/n)"

# If response is empty or 'Y', shutdown the computer
if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
    Stop-Computer -ComputerName $ComputerName -Force -Verbose
}


$response = Read-Host -Prompt "Start $ComputerName via AzureRM? (Y/n)"

# If response is empty or 'Y', start the Azure VM
# And if response is 'n', exit the script
if ($request -eq 'n' -or $request -eq 'N') {
    exit
}
if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
    Start-AzVM -ResourceGroupName $AzResourceGroupName -Name $AzName
}

# Function to stop and start the Azure VM
function Restart-AzVM {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $Name -Force
    Start-AzVM -ResourceGroupName $ResourceGroupName -Name $Name -Force
}

# Loop until the connection is successful
while ($true) {
    # Calculate the timeout time
    $timeout = (Get-Date).AddMinutes(5)

    # Loop until the connection is successful or the timeout is reached
    while ((Get-Date) -lt $timeout) {
        if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet) {
            Write-Host "Connection successful"
            # If the connection is successful, exit the loop
            break
        }

        # Wait for a bit before trying again
        Write-Host "Connection failed, waiting 10 seconds"
        Start-Sleep -Seconds 10
    }

    # If the connection is not successful, stop and start the Azure VM
    Write-Host "Connection failed, restarting Azure VM"
    Restart-AzVM -ResourceGroupName $AzResourceGroupName -Name $AzName
}
Write-Host "Successfully updated and restarted $ComputerName"

# add * if taskpath's end is not *
if ($Taskpath.Substring($Taskpath.Length - 1) -ne "*") {
    $Taskpath = $Taskpath + "*"
}
Get-ScheduledTask -CimSession $ComputerName -Taskpath $Taskpath