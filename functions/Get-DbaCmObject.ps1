function Get-DbaCmObject {
    <#
    .SYNOPSIS
    Retrieves Wmi/Cim-Style information from computers.

    .DESCRIPTION
    This function centralizes all requests for information retrieved from Get-WmiObject or Get-CimInstance.
    It uses different protocols as available in this order:
        - Cim over WinRM
        - Cim over DCOM
        - Wmi
        - Wmi over PowerShell Remoting
    It remembers channels that didn't work and will henceforth avoid them. It remembers invalid credentials and will avoid reusing them.
    Much of its behavior can be configured using Test-DbaWmConnection.

    .PARAMETER ClassName
    The name of the class to retrieve.
	
	.PARAMETER Query
	The Wmi/Cim query tu run against the server.

    .PARAMETER ComputerName
    The computer(s) to connect to. Defaults to localhost.

    .PARAMETER Credential
    Credentials to use. Invalid credentials will be stored in a credentials cache and not be reused.

    .PARAMETER Namespace
    The namespace of the class to use.

    .PARAMETER DoNotUse
    Connection Protocols that should not be used.

    .PARAMETER Force
    Overrides some checks that might otherwise halt execution as a precaution
    - Ignores timeout on bad connections
	
	.PARAMETER SilentlyContinue
	Use in conjunction with the -Silent switch.
	By default, Get-DbaCmObject will throw a terminating exception when connecting to a target is impossible in silent mode.
	Setting this switch will cause it write a non-terminating exception and continue with the next computer.

    .PARAMETER Silent
    Replaces user friendly yellow warnings with bloody red exceptions of doom!
    Use this if you want the function to throw terminating errors you want to catch.

	.NOTES
	Original Author: Fred Winmann (@FredWeinmann)
	Tags: ComputerManagement

	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaCmObject

    .EXAMPLE
    Get-DbaCmObject win32_OperatingSystem

    Retrieves the common operating system informations from the local computer.

    .EXAMPLE
    Get-DbaCmObject -Computername "sql2014" -ClassName Win32_OperatingSystem -Credential $cred -DoNotUse CimRM

    Retrieves the common operating system informations from the server sql2014.
    It will use the credewntials stored in $cred to connect, unless they are known to not work, in which case they will default to windows credentials (unless another default has been set).
    #>
    [CmdletBinding(DefaultParameterSetName = "Class")]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Class")]
        [Alias('Class')]
        [string]
        $ClassName,

        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Query")]
        [string]
        $Query,

        [Parameter(ValueFromPipeline = $true)]
        [sqlcollective.dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,

        [System.Management.Automation.PSCredential]
        $Credential,

        [string]
        $Namespace = "root\cimv2",

        [sqlcollective.dbatools.Connection.ManagementConnectionType[]]
        $DoNotUse = "None",

        [switch]
        $Force,

        [switch]
        $SilentlyContinue,

        [switch]
        $Silent
    )

    Begin {
        #region Configuration Values
        $disable_cache = Get-DbaConfigValue -Name 'ComputerManagement.Cache.Disable.All' -Fallback $false
        $disable_badcredentialcache = Get-DbaConfigValue -Name 'ComputerManagement.Cache.Disable.BadCredentialList' -Fallback $false

        $disable_CimRM = Get-DbaConfigValue -Name 'ComputerManagement.Type.Disable.CimRM' -Fallback $false
        $disable_CimDCOM = Get-DbaConfigValue -Name 'ComputerManagement.Type.Disable.CimDCOM' -Fallback $false
        $disable_WMI = Get-DbaConfigValue -Name 'ComputerManagement.Type.Disable.WMI' -Fallback $false
        $disable_PowerShellRemoting = Get-DbaConfigValue -Name 'ComputerManagement.Type.Disable.PowerShellRemoting' -Fallback $false

        Write-Message -Level Verbose -Message "Configuration loaded | Cache disabled: $disable_cache | Bad Credential Cache disabled: $disable_badcredentialcache | CimRM disabled: $disable_CimRM | CimDCOM disabled: $disable_CimDCOM | Wmi disabled: $disable_WMI | PowerShellRemoting disabled: $disable_PowerShellRemoting"
        #endregion Configuration Values

        $ParSet = $PSCmdlet.ParameterSetName
    }
    Process {
        :main foreach ($connectionObject in $ComputerName) {
            if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret input: $($connectionObject.Input)" -Category InvalidArgument -Target $connectionObject.Input -Continue -SilentlyContinue:$SilentlyContinue }

            # Since all connection caching runs using lower-case strings, making it lowercase here simplifies things.
            $computer = $connectionObject.Connection.ComputerName.ToLower()

            Write-Message -Message "[$computer] Retrieving Management Information" -Level VeryVerbose -Target $computer

            $connection = $connectionObject.Connection

            # Ensure using the right credentials
            try { $cred = $connection.GetCredential($Credential) }
            catch {
                $message = "Bad credentials! "
                if ($Credential) { $message += "The credentials for $($Credential.UserName) are known to not work. " }
                else { $message += "The windows credentials are known to not work. " }
                if ($connection.EnableCredentialFailover -or $connection.OverrideExplicitCredential) { $message += "The connection is configured to use credentials that are known to be good, but none have been registered yet. " }
                elseif ($connection.Credentials) { $message += "Working credentials are known for $($connection.Credentials.UserName), however the connection is not configured to automatically use them. This can be done using 'Set-DbaCmConnection -ComputerName $connection -OverrideExplicitCredential' " }
                elseif ($connection.UseWindowsCredentials) { $message += "The windows credentials are known to work, however the connection is not configured to automatically use them. This can be done using 'Set-DbaCmConnection -ComputerName $connection -OverrideExplicitCredential' " }
                $message += $_.Exception.Message
                Stop-Function -Message $message -InnerErrorRecord $_ -Target $connection -Continue
            }

            # Create list of excluded connection types (Duplicates don't matter)
            $excluded = @()
            foreach ($item in $DoNotUse) { $excluded += $item }
            if ($disable_CimRM) { $excluded += "CimRM" }
            if ($disable_CimDCOM) { $excluded += "CimDCOM" }
            if ($disable_WMI) { $excluded += "Wmi" }
            if ($disable_PowerShellRemoting) { $excluded += "PowerShellRemoting" }

            :sub while ($true) {
                try { $conType = $connection.GetConnectionType(($excluded -join ","), $Force) }
                catch {
                    if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                    Stop-Function -Message "[$computer] Could not find a valid connection protocol, interrupting execution now" -Target $computer -Category OpenError -Continue -ContinueLabel "main" -SilentlyContinue:$SilentlyContinue -ErrorRecord $_
                }

                switch ($conType.ToString()) {
                    #region CimRM
                    "CimRM" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM"
                        try {
                            switch ($ParSet) {
                                "Class" { $connection.GetCimRMInstance($cred, $ClassName, $Namespace) }
                                "Query" { $connection.QueryCimRMInstance($cred, $Query, "WQL", $Namespace) }
                            }

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM - Success!"
                            $connection.ReportSuccess('CimRM')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        }
                        catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM - Failed!"
                            if ($Session) { Remove-CimSession -CimSession $Session }

                            if ($_.FullyQualifiedErrorId -eq "UnauthorizedAccessException") {
                                # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                $connection.AddBadCredential($cred)
                                if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -InnerErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            }
                            elseif ($_.Exception.InnerException.MessageId -eq "HRESULT 0x80338000") {
                                Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -InnerErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            }
                            else {
                                $connection.ReportFailure('CimRM')
                                $excluded += "CimRM"
                                continue sub
                            }
                        }
                    }
                    #endregion CimRM

                    #region CimDCOM
                    "CimDCOM" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM"
                        try {
                            switch ($ParSet) {
                                "Class" { $connection.GetCimDCOMInstance($cred, $ClassName, $Namespace) }
                                "Query" { $connection.QueryCimDCOMInstance($cred, $Query, "WQL", $Namespace) }
                            }

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM - Success!"
                            $connection.ReportSuccess('CimDCOM')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        }
                        catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM - Failed!"
                            if ($Session) { Remove-CimSession -CimSession $Session }

                            if ($_.FullyQualifiedErrorId -eq "UnauthorizedAccessException") {
                                # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                $connection.AddBadCredential($cred)
                                if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -InnerErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            }
                            elseif ($_.Exception.InnerException.MessageId -eq "HRESULT 0x80338000") {
                                Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -InnerErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            }
                            else {
                                $connection.ReportFailure('CimDCOM')
                                $excluded += "CimDCOM"
                                continue sub
                            }
                        }
                    }
                    #endregion CimDCOM

                    #region Wmi
                    "Wmi" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI"
						try {
							switch ($ParSet) {
								"Class" {
									$parameters = @{
										ComputerName = $computer
										ClassName = $ClassName
										ErrorAction = 'Stop'
									}
									if ($cred) { $parameters["Credential"] = $cred }
									if (Was-Bound "Namespace") { $parameters["Namespace"] = $Namespace }
									
								}
								"Query" {
									$parameters = @{
										ComputerName = $computer
										Query = $Query
										ErrorAction = 'Stop'
									}
									if ($cred) { $parameters["Credential"] = $cred }
									if (Was-Bound "Namespace") { $parameters["Namespace"] = $Namespace }
								}
							}
							
							Get-WmiObject @parameters

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI - Success!"
                            $connection.ReportSuccess('Wmi')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        }
                        catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI - Failed!" -ErrorRecord $_

                            if ($_.CategoryInfo.Reason -eq "UnauthorizedAccessException") {
                                # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                $connection.AddBadCredential($cred)
                                if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            }
                            elseif ($_.CategoryInfo.Category -eq "InvalidType") {
                                Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            }
                            else {
                                $connection.ReportFailure('Wmi')
                                $excluded += "Wmi"
                                continue sub
                            }
                        }
                    }
                    #endregion Wmi

                    #region PowerShell Remoting
                    "PowerShellRemoting" {
                        try {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using PowerShell Remoting"
                            $scp_string = "Get-WmiObject -Class $ClassName -ErrorAction Stop"
                            if ($PSBoundParameters.ContainsKey("Namespace")) { $scp_string += " -Namespace $Namespace" }

                            $parameters = @{
                                ScriptBlock  = ([System.Management.Automation.ScriptBlock]::Create($scp_string))
                                ComputerName = $ComputerName
                                ErrorAction  = 'Stop'
                            }
                            if ($Credential) { $parameters["Credential"] = $Credential }
                            Invoke-Command @parameters

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using PowerShell Remoting - Success!"
                            $connection.ReportSuccess('PowerShellRemoting')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        }
                        catch {
                            # Will always consider authenticated, since any call with credentials to a server that doesn't exist will also carry invalid credentials error.
                            # There simply is no way to differentiate between actual authentication errors and server not reached
                            $connection.ReportFailure('PowerShellRemoting')
                            $excluded += "PowerShellRemoting"
                            continue sub
                        }
                    }
                    #endregion PowerShell Remoting
                }
            }
        }
    }
    End {

    }
}