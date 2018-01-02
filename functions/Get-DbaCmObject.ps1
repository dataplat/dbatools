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
        Use in conjunction with the -EnableException switch.
        By default, Get-DbaCmObject will throw a terminating exception when connecting to a target is impossible in exception enabled mode.
        Setting this switch will cause it write a non-terminating exception and continue with the next computer.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        Get-DbaCmObject win32_OperatingSystem

        Retrieves the common operating system informations from the local computer.

    .EXAMPLE
        Get-DbaCmObject -Computername "sql2014" -ClassName Win32_OperatingSystem -Credential $cred -DoNotUse CimRM

        Retrieves the common operating system informations from the server sql2014.
        It will use the credewntials stored in $cred to connect, unless they are known to not work, in which case they will default to windows credentials (unless another default has been set).

    .NOTES
        Author: Fred Winmann (@FredWeinmann)
        Tags: ComputerManagement

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Get-DbaCmObject
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
        [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,

        [System.Management.Automation.PSCredential]
        $Credential,

        [string]
        $Namespace = "root\cimv2",

        [Sqlcollaborative.Dbatools.Connection.ManagementConnectionType[]]
        $DoNotUse = "None",

        [switch]
        $Force,

        [switch]
        $SilentlyContinue,

        [switch]
        [Alias('Silent')]$EnableException
    )

    Begin {
        #region Configuration Values
        $disable_cache = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableCache

        Write-Message -Level Verbose -Message "Configuration loaded | Cache disabled: $disable_cache"
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
                Stop-Function -Message $message -ErrorRecord $_ -Target $connection -Continue -OverrideExceptionMessage
            }

            # Flags-Enumerations cannot be added in PowerShell 4 or older.
            # Thus we create a string and convert it afterwards.
            $enabledProtocols = "None"
            if ($connection.CimRM -notlike "Disabled") { $enabledProtocols += ", CimRM" }
            if ($connection.CimDCOM -notlike "Disabled") { $enabledProtocols += ", CimDCOM" }
            if ($connection.Wmi -notlike "Disabled") { $enabledProtocols += ", Wmi" }
            if ($connection.PowerShellRemoting -notlike "Disabled") { $enabledProtocols += ", PowerShellRemoting" }
            [Sqlcollaborative.Dbatools.Connection.ManagementConnectionType]$enabledProtocols = $enabledProtocols

            # Create list of excluded connection types (Duplicates don't matter)
            $excluded = @()
            foreach ($item in $DoNotUse) { $excluded += $item }

            :sub while ($true) {
                try { $conType = $connection.GetConnectionType(($excluded -join ","), $Force) }
                catch {
                    if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                    Stop-Function -Message "[$computer] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: $enabledProtocols" -Target $computer -Category OpenError -Continue -ContinueLabel "main" -SilentlyContinue:$SilentlyContinue -ErrorRecord $_
                }

                switch ($conType.ToString()) {
                    #region CimRM
                    "CimRM" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM"
                        try {
                            if ($ParSet -eq "Class") { $connection.GetCimRMInstance($cred, $ClassName, $Namespace) }
                            else { $connection.QueryCimRMInstance($cred, $Query, "WQL", $Namespace) }

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM - Success!"
                            $connection.ReportSuccess('CimRM')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        }
                        catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM - Failed!"

                            # 1 = Generic runtime error
                            if ($_.Exception.InnerException.StatusCode -eq 1) {
                                # 0x8007052e, 0x80070005 : Authentication error, bad credential
                                if (($_.Exception.InnerException -eq 0x8007052e) -or ($_.Exception.InnerException -eq 0x80070005)) {
                                    # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                    # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                    $connection.AddBadCredential($cred)
                                    if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                    Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                                }
                                elseif ($_.Exception.InnerException.MessageId -eq "HRESULT 0x80041013") {
                                    if ($ParSet -eq "Class") { Stop-Function -Message "[$computer] Failed to access $class in namespace $Namespace!" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -Exception $_.Exception.InnerException }
                                    else { Stop-Function -Message "[$computer] Failed to execute $query in namespace $Namespace!" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -Exception $_.Exception.InnerException }
                                }
                                else {
                                    $connection.ReportFailure('CimRM')
                                    $excluded += "CimRM"
                                    continue sub
                                }
                            }

                            # 2 = Access to specific resource denied
                            elseif ($_.Exception.InnerException.StatusCode -eq 2) {
                                Stop-Function -Message "[$computer] Access to computer granted, but access to $Namespace\$ClassName denied!" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                            }

                            # 3 = Invalid Namespace
                            elseif ($_.Exception.InnerException.StatusCode -eq 3) {
                                Stop-Function -Message "[$computer] Invalid namespace: $Namespace" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                            }
                            # 5 = Invalid Class
                            # See here for code reference: https://msdn.microsoft.com/en-us/library/cc150671(v=vs.85).aspx
                            elseif ($_.Exception.InnerException.StatusCode -eq 5) {
                                Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                            }

                            # 0 & ExtendedStatus = Weird issue beyond the scope of the CIM standard. Often a server-side issue
                            elseif (($_.Exception.InnerException.StatusCode -eq 0) -and ($_.Exception.InnerException.ErrorData.original_error -like "__ExtendedStatus")) {
                                Stop-Function -Message "[$computer] Something went wrong when looking for $ClassName, in $Namespace. This often indicates issues with the target system." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
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
                            if ($ParSet -eq "Class") { $connection.GetCimDCOMInstance($cred, $ClassName, $Namespace) }
                            else { $connection.QueryCimDCOMInstance($cred, $Query, "WQL", $Namespace) }

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM - Success!"
                            $connection.ReportSuccess('CimDCOM')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        }
                        catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM - Failed!"

                            # 1 = Generic runtime error
                            if ($_.Exception.InnerException.StatusCode -eq 1) {
                                # 0x8007052e, 0x80070005 : Authentication error, bad credential
                                if (($_.Exception.InnerException -eq 0x8007052e) -or ($_.Exception.InnerException -eq 0x80070005)) {
                                    # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                    # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                    $connection.AddBadCredential($cred)
                                    if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                    Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                                }
                                elseif ($_.Exception.InnerException.MessageId -eq "HRESULT 0x80041013") {
                                    if ($ParSet -eq "Class") { Stop-Function -Message "[$computer] Failed to access $class in namespace $Namespace!" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -Exception $_.Exception.InnerException }
                                    else { Stop-Function -Message "[$computer] Failed to execute $query in namespace $Namespace!" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -Exception $_.Exception.InnerException }
                                }
                                else {
                                    $connection.ReportFailure('CimDCOM')
                                    $excluded += "CimDCOM"
                                    continue sub
                                }
                            }

                            # 2 = Access to specific resource denied
                            elseif ($_.Exception.InnerException.StatusCode -eq 2) {
                                Stop-Function -Message "[$computer] Access to computer granted, but access to $Namespace\$ClassName denied!" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                            }

                            # 3 = Invalid Namespace
                            elseif ($_.Exception.InnerException.StatusCode -eq 3) {
                                Stop-Function -Message "[$computer] Invalid namespace: $Namespace" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                            }

                            # 5 = Invalid Class
                            # See here for code reference: https://msdn.microsoft.com/en-us/library/cc150671(v=vs.85).aspx
                            elseif ($_.Exception.InnerException.StatusCode -eq 5) {
                                Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                            }

                            # 0 & ExtendedStatus = Weird issue beyond the scope of the CIM standard. Often a server-side issue
                            elseif (($_.Exception.InnerException.StatusCode -eq 0) -and ($_.Exception.InnerException.ErrorData.original_error -like "__ExtendedStatus")) {
                                Stop-Function -Message "[$computer] Something went wrong when looking for $ClassName, in $Namespace. This often indicates issues with the target system." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
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
                                        ClassName    = $ClassName
                                        ErrorAction  = 'Stop'
                                    }
                                    if ($cred) { $parameters["Credential"] = $cred }
                                    if (Test-Bound "Namespace") { $parameters["Namespace"] = $Namespace }

                                }
                                "Query" {
                                    $parameters = @{
                                        ComputerName = $computer
                                        Query        = $Query
                                        ErrorAction  = 'Stop'
                                    }
                                    if ($cred) { $parameters["Credential"] = $cred }
                                    if (Test-Bound "Namespace") { $parameters["Namespace"] = $Namespace }
                                }
                            }

                            Get-WmiObject @parameters

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI - Success!"
                            $connection.ReportSuccess('Wmi')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        }
                        catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI - Failed!" -ErrorRecord $_

                            if ($_.CategoryInfo.Reason -eq "UnauthorizedAccessException") {
                                # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                $connection.AddBadCredential($cred)
                                if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            }
                            elseif ($_.CategoryInfo.Category -eq "InvalidType") {
                                Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            }
                            elseif ($_.Exception.ErrorCode -eq "ProviderLoadFailure") {
                                Stop-Function -Message "[$computer] Failed to access: $ClassName, in namespace: $Namespace - There was a provider error. This indicates a potential issue with WMI on the server side." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
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
                            if (-not $disable_cache) { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
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
