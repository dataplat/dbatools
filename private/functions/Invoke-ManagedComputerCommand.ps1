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
        Invoke-Command2 @parms
    } catch {
        Write-Message -Level Verbose -Message "Local connection attempt to $computer failed | $PSItem. Connecting remotely."
        $hostname = $resolved.FullComputerName

        # For surely resolve stuff, and going by default with kerberos, this needs to match FullComputerName

        try {
            Invoke-Command2 @parms -ComputerName $hostname
        } catch {
            try {
                $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 16
                $parms.ArgumentList = $ArgumentList
                Invoke-Command2 @parms -ComputerName $hostname
            } catch {
                # lol I'm not sure how to catch the last error so...
                try {
                    $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 15
                    $parms.ArgumentList = $ArgumentList
                    Invoke-Command2 @parms -ComputerName $hostname
                } catch {
                    try {
                        $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 14
                        $parms.ArgumentList = $ArgumentList
                        Invoke-Command2 @parms -ComputerName $hostname
                    } catch {
                        try {
                            $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 13
                            $parms.ArgumentList = $ArgumentList
                            Invoke-Command2 @parms -ComputerName $hostname
                        } catch {
                            try {
                                $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 12
                                $parms.ArgumentList = $ArgumentList
                                Invoke-Command2 @parms -ComputerName $hostname
                            } catch {
                                try {
                                    $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 11
                                    $parms.ArgumentList = $ArgumentList
                                    Invoke-Command2 @parms -ComputerName $hostname
                                } catch {
                                    try {
                                        $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 10
                                        $parms.ArgumentList = $ArgumentList
                                        Invoke-Command2 @parms -ComputerName $hostname
                                    } catch {
                                        try {
                                            $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 9
                                            $parms.ArgumentList = $ArgumentList
                                            Invoke-Command2 @parms -ComputerName $hostname
                                        } catch {
                                            $ArgumentList[$ArgumentList.GetUpperBound(0)].version = 8
                                            $parms.ArgumentList = $ArgumentList
                                            Invoke-Command2 @parms -ComputerName $hostname
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}