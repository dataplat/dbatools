function Invoke-ManagedComputerCommand {
    <#
        .SYNOPSIS
            Runs wmi commands against a target system.

        .DESCRIPTION
            Runs wmi commands against a target system.
            Either directly or over PowerShell remoting.

        .PARAMETER ComputerName
            The target to run against. Must be resolvable.

        .PARAMETER Credential
            Credentials to use when using PowerShell remoting.

        .PARAMETER ScriptBlock
            The scriptblock to execute.
            Use $wmi to access the smo wmi object.
            Must not include a param block!

        .PARAMETER ArgumentList
            The arguments to pass to your scriptblock.
            Access them within the scriptblock using the automatic variable $args

        .PARAMETER EnableException
            Left in for legacy reasons. This command will throw no matter what
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias("Server")]
        [dbainstanceparameter]$ComputerName,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [switch]$EnableException # Left in for legacy but this command needs to throw
    )

    $computer = $ComputerName.ComputerName

    $null = Test-ElevationRequirement -ComputerName $computer -EnableException $true

    $resolved = Resolve-DbaNetworkName -ComputerName $computer -Turbo
    $ipaddr = $resolved.IpAddress

    $additionalArgumentList = [PSCustomObject]@{
        ipaddr  = $ipaddr
        version = 0
    }
    $ArgumentList += $additionalArgumentList

    [scriptblock]$setupScriptBlock = {
        $ipaddr = $args[$args.GetUpperBound(0)].ipaddr
        $version = $args[$args.GetUpperBound(0)].version

        $setupVerbose = @( )
        $setupVerbose += "Starting WMI initialization at $ipaddr"

        if ($version -eq 0) {
            $setupVerbose += "Using latest version"
            $null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
        } else {
            $setupVerbose += "Attempting specific version $version"
            $dll = Get-ChildItem $env:windir\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.SqlWmiManagement, $env:windir\assembly\GAC_MSIL\Microsoft.SqlServer.SqlWmiManagement -Recurse -File | Where-Object FullName -like "*$version.0*"

            if ($dll.FullName) {
                $setupVerbose += "Loading from $($dll.FullName)"
                $null = Add-Type -Path $dll.FullName
            } else {
                $setupVerbose += "Could not find matching version $version"
            }
        }
        # Just in case we go remote, ensure the assembly is loaded

        $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $ipaddr
        $result = $wmi.Initialize()
        $setupVerbose += "Finished WMI initialization with $result"
    }

    $prescriptblock = $setupScriptBlock.ToString()
    $postscriptblock = $ScriptBlock.ToString()

    $scriptBlock = [ScriptBlock]::Create("$prescriptblock  $postscriptblock")
    Write-Message -Level Verbose -Message "Connecting to SQL WMI on $computer."

    $parms = @{
        ScriptBlock  = $ScriptBlock
        ArgumentList = $ArgumentList
        Credential   = $Credential
        ErrorAction  = 'Stop'
    }

    try {
        # Attempt to execute the command directly
        Invoke-Command2 @parms
    } catch {
        # Log the failure and prepare to connect remotely
        Write-Message -Level Verbose -Message "Local connection attempt to $computer failed | $PSItem. Connecting remotely."
        $hostname = $resolved.FullComputerName

        # For securely resolving and using Kerberos by default, the ComputerName should match FullComputerName
        # Now, we will attempt to connect remotely with different versions

        # Set the maximum and minimum versions for the loop
        $MaxVersion = 16
        $MinVersion = 8

        # Iterate through versions from maximum to minimum
        foreach ($version in ($MaxVersion..$MinVersion)) {
            try {
                # Set the desired version in the ArgumentList
                $ArgumentList[$ArgumentList.GetUpperBound(0)].version = $version
                $parms.ArgumentList = $ArgumentList

                # Attempt to execute the command remotely
                Invoke-Command2 @parms -ComputerName $hostname

                # Operation succeeded, exit the loop
                break
            } catch {
                # Log the failure and proceed to the next version
                Write-Message -Level Verbose -Message "Local connection attempt to $computer failed | $PSItem. Connecting remotely (Version $version)."
            }
        }
    }
}