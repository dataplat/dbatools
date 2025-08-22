function Get-DbaCmObject {
    <#
    .SYNOPSIS
        Retrieves Windows system information from SQL Server hosts using WMI/CIM with intelligent connection fallback.

    .DESCRIPTION
        Queries Windows Management Instrumentation (WMI) or Common Information Model (CIM) classes on SQL Server hosts to gather system-level information like hardware specs, operating system details, services, and performance counters. This function automatically tries multiple connection protocols in order of preference (CIM over WinRM, CIM over DCOM, WMI, then WMI over PowerShell Remoting) and remembers which methods work for each server to optimize future connections.

        Essential for collecting host-level information that complements SQL Server monitoring, such as checking available memory, CPU utilization, disk space, or Windows service status across your SQL Server infrastructure. The intelligent credential and connection caching prevents repeated authentication failures and speeds up bulk operations across multiple servers.

        Much of its behavior can be configured using Test-DbaCmConnection to pre-test and configure optimal connection methods for your environment.

    .PARAMETER ClassName
        The name of the class to retrieve.

    .PARAMETER Query
        The Wmi/Cim query to run against the server.

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

    .NOTES
        Tags: ComputerManagement, CIM
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCmObject

    .EXAMPLE
        PS C:\> Get-DbaCmObject win32_OperatingSystem

        Retrieves the common operating system information from the local computer.

    .EXAMPLE
        PS C:\> Get-DbaCmObject -Computername "sql2014" -ClassName Win32_OperatingSystem -Credential $cred -DoNotUse CimRM

        Retrieves the common operating system information from the server sql2014.
        It will use the Credentials stored in $cred to connect, unless they are known to not work, in which case they will default to windows credentials (unless another default has been set).
    #>
    [CmdletBinding(DefaultParameterSetName = "Class")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWMICmdlet", "", Justification = "Using Get-WmiObject is used as a fallback for gathering information")]
    param (
        [Parameter(Mandatory, ParameterSetName = "Class", Position = 0)]
        [Alias('Class')]
        [string]$ClassName,
        [Parameter(Mandatory, ParameterSetName = "Query")]
        [string]$Query,
        [Parameter(ValueFromPipeline)]
        [Dataplat.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$Namespace = "root\cimv2",
        [Dataplat.Dbatools.Connection.ManagementConnectionType[]]
        $DoNotUse = "None",
        [switch]$Force,
        [switch]$SilentlyContinue,
        [switch]$EnableException
    )

    begin {
        #region Configuration Values
        $disable_cache = [Dataplat.Dbatools.Connection.ConnectionHost]::DisableCache

        Write-Message -Level Verbose -Message "Configuration loaded | Cache disabled: $disable_cache"
        #endregion Configuration Values

        #region Utility Functions
        function Resolve-CimError {
            <#
                .SYNOPSIS
                    Utility function to resolve CIM error states and streamline error handling in code.

                .DESCRIPTION
                    Utility function to resolve CIM error states and streamline error handling in code.
                    This determines the specific error message to provide and whether the connection type is not viable.

                    CIM Error Code Reference: https://msdn.microsoft.com/en-us/library/cc150671(v=vs.85).aspx

                .PARAMETER ErrorRecord
                    The error that just happened.

                .PARAMETER ComputerName
                    The computer against which the query was executed.

                .PARAMETER ClassName
                    The name of the class queried.

                .PARAMETER Namespace
                    The namespace executed against.

                .PARAMETER Query
                    The query executed.
            #>
            [CmdletBinding()]
            param (
                [System.Management.Automation.ErrorRecord]
                $ErrorRecord,

                [string]
                $ComputerName,

                [AllowEmptyString()]
                [string]
                $ClassName,

                [AllowEmptyString()]
                [string]
                $Namespace,

                [AllowEmptyString()]
                [string]
                $Query
            )

            if ($Query) {
                $ClassName = $Query -replace '.+from (\S+).{0,}', '$1'
            }

            $messages = @{
                1  = "[$ComputerName] An otherwise unexpected error happened."
                2  = "[$ComputerName] Access to computer granted, but access to $Namespace\$ClassName denied"
                3  = "[$ComputerName] Invalid namespace: $Namespace"
                4  = "[$ComputerName] Invalid parameters were specified"
                5  = "[$ComputerName] Invalid class name ($ClassName), not found in current namespace ($Namespace)"
                6  = "[$ComputerName] The requested object of class $ClassName could not be found"
                7  = "[$ComputerName] The operation against class $ClassName was not supported. This generally is a serverside WMI Provider issue (That is: It is specific to the application being managed via WMI)"
                8  = "[$ComputerName] The operation against class $ClassName is refused as long as it contains instances (data)"
                9  = "[$ComputerName] The operation against class $ClassName is refused as long as it contains instances (data)"
                10 = "[$ComputerName] The operation against class $ClassName cannot be carried out since the specified superclass does not exist."
                11 = "[$ComputerName] The specified object in $ClassName already exists."
                12 = "[$ComputerName] The specified property does not exist on $ClassName."
                13 = "[$ComputerName] The input type is invalid."
                14 = "[$ComputerName] Invalid query language. Please check your query string."
                15 = "[$ComputerName] Invalid query string. Please check your syntax."
                16 = "[$ComputerName] The specified method on $ClassName is not available."
                17 = "[$ComputerName] The specified method on $ClassName does not exist."
                18 = "[$ComputerName] An unexpected response has happened in this request"
                19 = "[$ComputerName] The specified destination for this request is invalid."
                20 = "[$ComputerName] The specified namespace $Namespace is not empty."
            }

            $badConnection = $false
            $badCredentials = $false
            $code = $ErrorRecord.Exception.InnerException.StatusCode -as [int]
            $message = $messages[$code]

            #region 1 = Generic runtime error
            # This routinely happens with CIM/DCOM
            if (1 -eq $code) {
                switch ($ErrorRecord.Exception.InnerException.MessageId) {
                    'HRESULT 0x8007052e' {
                        $badCredentials = $true
                        $message = "[$ComputerName] Invalid connection credentials"
                    }
                    'HRESULT 0x80070005' {
                        $badCredentials = $true
                        $message = "[$ComputerName] Invalid connection credentials"
                    }
                    'HRESULT 0x80041013' {
                        $message = "[$ComputerName] Failed to access $ClassName in namespace $Namespace"
                    }
                    'HRESULT 0x8004100e' {
                        $message = "[$ComputerName] Invalid namespace: $Namespace"
                        $code = 3
                    }
                    'HRESULT 0x80041010' {
                        $message = "[$ComputerName] Invalid class name ($ClassName), not found in current namespace ($Namespace)"
                        $code = 5
                    }
                    default {
                        $badConnection = $true
                    }
                }
            }
            #endregion 1 = Generic runtime error

            #region 0 = Non-CIM Issue not covered by the framework
            $knownCodes = 1..20
            if ($code -notin $knownCodes) {
                if ($ErrorRecord.Exception.InnerException.ErrorData.original_error -like "__ExtendedStatus") {
                    $message = "[$ComputerName] Something went wrong when looking for $ClassName, in $Namespace. This often indicates issues with the target system."
                } else {
                    $badConnection = $true
                }
            }
            #endregion 0 = Non-CIM Issue not covered by the framework

            [PSCustomObject]@{
                ErrorCode      = $code
                Message        = $message
                BadConnection  = $badConnection
                BadCredentials = $badCredentials
                Error          = $ErrorRecord
            }
        }
        #endregion Utility Functions

        $ParSet = $PSCmdlet.ParameterSetName
    }
    process {
        # uses cim commands
        :main foreach ($connectionObject in $ComputerName) {
            if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret input: $($connectionObject.Input)" -Category InvalidArgument -Target $connectionObject.Input -Continue -SilentlyContinue:$SilentlyContinue }

            # Since all connection caching runs using lower-case strings, making it lowercase here simplifies things.
            $computer = $connectionObject.Connection.ComputerName.ToLowerInvariant()

            Write-Message -Message "[$computer] Retrieving Management Information" -Level VeryVerbose -Target $computer

            $connection = $connectionObject.Connection

            # Ensure using the right credentials
            try { $cred = $connection.GetCredential($Credential) }
            catch {
                $message = "Bad credentials. "
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
            [Dataplat.Dbatools.Connection.ManagementConnectionType]$enabledProtocols = $enabledProtocols

            # Create list of excluded connection types (Duplicates don't matter)
            $excluded = @()
            foreach ($item in $DoNotUse) { $excluded += $item }

            :sub while ($true) {
                try { $conType = $connection.GetConnectionType(($excluded -join ","), $Force) }
                catch {
                    if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                    Stop-Function -Message "[$computer] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: $enabledProtocols" -Target $computer -Category OpenError -Continue -ContinueLabel "main" -SilentlyContinue:$SilentlyContinue -ErrorRecord $_
                }

                switch ($conType.ToString()) {
                    #region CimRM
                    "CimRM" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM"
                        try {
                            if ($ParSet -eq "Class") { $connection.GetCimRMInstance($cred, $ClassName, $Namespace) }
                            else { $connection.QueryCimRMInstance($cred, $Query, "WQL", $Namespace) }

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM - Success"
                            $connection.ReportSuccess('CimRM')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        } catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over WinRM - Failed"
                            $errorDetails = Resolve-CimError -ErrorRecord $_ -ComputerName $computer -ClassName $ClassName -Namespace $Namespace -Query $Query

                            if ($errorDetails.BadCredentials) {
                                $connection.AddBadCredential($cred)
                                if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                            }
                            if ($errorDetails.BadConnection) {
                                $connection.ReportFailure('CimRM')
                                $excluded += "CimRM"
                                continue sub
                            }
                            Stop-Function -Message $errorDetails.Message -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                        }
                    }
                    #endregion CimRM

                    #region CimDCOM
                    "CimDCOM" {
                        Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM"
                        try {
                            if ($ParSet -eq "Class") { $connection.GetCimDCOMInstance($cred, $ClassName, $Namespace) }
                            else { $connection.QueryCimDCOMInstance($cred, $Query, "WQL", $Namespace) }

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM - Success"
                            $connection.ReportSuccess('CimDCOM')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        } catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using Cim over DCOM - Failed"
                            $errorDetails = Resolve-CimError -ErrorRecord $_ -ComputerName $computer -ClassName $ClassName -Namespace $Namespace -Query $Query

                            if ($errorDetails.BadCredentials) {
                                $connection.AddBadCredential($cred)
                                if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
                            }
                            if ($errorDetails.BadConnection) {
                                $connection.ReportFailure('CimDCOM')
                                $excluded += "CimDCOM"
                                continue sub
                            }
                            Stop-Function -Message $errorDetails.Message -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue -OverrideExceptionMessage
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

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI - Success"
                            $connection.ReportSuccess('Wmi')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        } catch {
                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using WMI - Failed" -ErrorRecord $_

                            if ($_.CategoryInfo.Reason -eq "UnauthorizedAccessException") {
                                # Ignore the global setting for bad credential cache disabling, since the connection object is aware of that state and will ignore input if it should.
                                # This is due to the ability to locally override the global setting, thus it must be done on the object and can then be done in code
                                $connection.AddBadCredential($cred)
                                if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                                Stop-Function -Message "[$computer] Invalid connection credentials" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            } elseif ($_.CategoryInfo.Category -eq "InvalidType") {
                                Stop-Function -Message "[$computer] Invalid class name ($ClassName), not found in current namespace ($Namespace)" -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            } elseif ($_.Exception.ErrorCode -eq "ProviderLoadFailure") {
                                Stop-Function -Message "[$computer] Failed to access: $ClassName, in namespace: $Namespace - There was a provider error. This indicates a potential issue with WMI on the server side." -Target $computer -Continue -ContinueLabel "main" -ErrorRecord $_ -SilentlyContinue:$SilentlyContinue
                            } else {
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
                                ComputerName = $computer
                                Raw          = $true
                            }
                            if ($Credential) { $parameters["Credential"] = $Credential }
                            Invoke-Command2 @parameters

                            Write-Message -Level Verbose -Message "[$computer] Accessing computer using PowerShell Remoting - Success"
                            $connection.ReportSuccess('PowerShellRemoting')
                            $connection.AddGoodCredential($cred)
                            if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$computer] = $connection }
                            continue main
                        } catch {
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
}