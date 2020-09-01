function Get-DbaDbccSessionBuffer {
    <#
    .SYNOPSIS
        Gets result of Database Console Command DBCC INPUTBUFFER  or DBCC OUTPUTBUFFER

    .DESCRIPTION
        Returns the results of DBCC INPUTBUFFER or DBCC OUTPUTBUFFER for input sessions

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-inputbuffer-transact-sql
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-outputbuffer-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Operation
        DBCC Operation to execute - either InputBuffer or OutputBuffer

    .PARAMETER SessionId
        The Session ID(s) to use to get current input or output buffer.

    .PARAMETER RequestId
        Is the exact request (batch) to search for within the current session
        The following query returns request_id:

        SELECT request_id
        FROM sys.dm_exec_requests
        WHERE session_id = @@spid;

    .PARAMETER All
        If this switch is enabled, results for all User Sessions will be retreived
        This overides any values for SessionId or RequestId

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbccSessionBuffer

    .EXAMPLE
        PS C:\> Get-DbaDbccSessionBuffer -SqlInstance Server1 -Operation InputBuffer -SessionId 51

        Get results of DBCC INPUTBUFFER(51) for Instance Server1

    .EXAMPLE
        PS C:\> Get-DbaDbccSessionBuffer -SqlInstance Server1 -Operation OutputBuffer -SessionId 51, 52

        Get results of DBCC OUTPUTBUFFER for SessionId's 51 and 52 for Instance Server1

    .EXAMPLE
        PS C:\> Get-DbaDbccSessionBuffer -SqlInstance Server1 -Operation InputBuffer -SessionId 51 -RequestId 0

        Get results of DBCC INPUTBUFFER(51,0) for Instance Server1

    .EXAMPLE
        PS C:\> Get-DbaDbccSessionBuffer -SqlInstance Server1 -Operation OutputBuffer -SessionId 51 -RequestId 0

        Get results of DBCC OUTPUTBUFFER(51,0) for Instance Server1

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbccSessionBuffer -Operation InputBuffer -All

        Get results of DBCC INPUTBUFFER for all user sessions for the instances Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbccSessionBuffer -Operation OutputBuffer -All

        Get results of DBCC OUTPUTBUFFER for all user sessions for the instances Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaDbccSessionBuffer -SqlInstance Server1 -SqlCredential $cred -Operation InputBuffer -SessionId 51 -RequestId 0

        Connects using sqladmin credential and gets results of DBCC INPUTBUFFER(51,0) for Instance Server1

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaDbccSessionBuffer -SqlInstance Server1 -SqlCredential $cred -Operation OutputBuffer -SessionId 51 -RequestId 0

        Connects using sqladmin credential and gets results of DBCC OUTPUTBUFFER(51,0) for Instance Server1

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('InputBuffer', 'OutputBuffer')]
        [string]$Operation = "InputBuffer",
        [int[]]$SessionId,
        [int]$RequestId,
        [switch]$All,
        [switch]$EnableException
    )
    begin {
        if (Test-Bound -Not -ParameterName All) {
            if (Test-Bound -Not -ParameterName SessionId) {
                Stop-Function -Message "You must specify either a SessionId or use the -All switch."
                return
            }
        }

        if (Test-Bound -ParameterName Operation) {
            $Operation = $Operation.ToUpper()
        }
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC $Operation(#Operation#) WITH NO_INFOMSGS")

    }
    process {

        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (Test-Bound -Not -ParameterName All) {
                foreach ($session_id in $SessionId) {
                    $query = $StringBuilder.ToString()

                    if (Test-Bound -Not -ParameterName RequestId) {
                        Write-Message -Message "Query to run: $query" -Level Verbose
                        $query = $query.Replace('#Operation#', $session_id)
                    } else {
                        Write-Message -Message "Query to run: $query" -Level Verbose
                        $query = $query.Replace('#Operation#', "$($session_id), $($RequestId)")
                    }

                    try {
                        Write-Message -Message "Query to run: $query" -Level Verbose
                        $results = $server.Query($query)
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                    }
                    if ($Operation -eq 'INPUTBUFFER') {
                        foreach ($row in $results) {
                            [PSCustomObject]@{
                                ComputerName = $server.ComputerName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                SessionId    = $session_id
                                EventType    = $row[0]
                                Parameters   = $row[1]
                                EventInfo    = $row[2]
                            }
                        }
                    } else {
                        Write-Message -Message "Output Buffer" -Level Verbose
                        $hexStringBuilder = New-Object System.Text.StringBuilder
                        $asciiStringBuilder = New-Object System.Text.StringBuilder

                        foreach ($row in $results) {
                            $str = $row[0].ToString()
                            $null = $hexStringBuilder.Append($str.Substring(11, 48))
                            $null = $asciiStringBuilder.Append($str.Substring(61, 16))
                        }
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            SessionId    = $session_id
                            Buffer       = $asciiStringBuilder.ToString().Replace('.', '').TrimEnd()
                            HexBuffer    = $hexStringBuilder.ToString().Replace(' ', '')
                        } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, SessionId, Buffer
                    }
                }
            } else {
                $sessionQuery = 'Select session_id FROM sys.dm_exec_connections'
                $sessionList = $server.Query($sessionQuery )
                foreach ($session in $sessionList) {
                    $query = $StringBuilder.ToString()
                    $query = $query.Replace('#Operation#', $session.session_id)
                    try {
                        Write-Message -Message "Query to run: $query" -Level Verbose
                        $results = $server.Query($query)
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                    }
                    if ($Operation -eq 'INPUTBUFFER') {
                        foreach ($row in $results) {
                            [PSCustomObject]@{
                                ComputerName = $server.ComputerName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                SessionId    = $session.session_id
                                EventType    = $row[0]
                                Parameters   = $row[1]
                                EventInfo    = $row[2]
                            }
                        }
                    } else {
                        $hexStringBuilder = New-Object System.Text.StringBuilder
                        $asciiStringBuilder = New-Object System.Text.StringBuilder

                        foreach ($row in $results) {
                            $str = $row[0].ToString()
                            $null = $hexStringBuilder.Append($str.Substring(11, 48))
                            $null = $asciiStringBuilder.Append($str.Substring(61, 16))
                        }
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            SessionId    = $session.session_id
                            Buffer       = $asciiStringBuilder.ToString().Replace('.', '').TrimEnd()
                            HexBuffer    = $hexStringBuilder.ToString().Replace(' ', '')
                        } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, SessionId, Buffer
                    }
                }
            }
        }
    }
}