function Get-DbaDbccSessionBuffer {
    <#
    .SYNOPSIS
        Retrieves session input or output buffer contents using DBCC INPUTBUFFER or DBCC OUTPUTBUFFER

    .DESCRIPTION
        Executes DBCC INPUTBUFFER or DBCC OUTPUTBUFFER to examine what SQL statements a session is executing or what data is being returned to a client. InputBuffer shows the last SQL batch sent by a client session, which is essential for troubleshooting blocking, investigating suspicious activity, or understanding what commands are causing performance issues. OutputBuffer reveals the actual data being transmitted back to the client, useful for debugging connectivity problems or examining result sets. This replaces the need to manually run DBCC commands and parse their output, especially when investigating multiple sessions simultaneously.

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
        Specifies which DBCC operation to execute: InputBuffer shows the last SQL statement sent by a client, while OutputBuffer shows data being returned to the client.
        Use InputBuffer when troubleshooting blocking sessions, investigating suspicious activity, or identifying problematic queries.
        Use OutputBuffer when debugging client connectivity issues or examining what data is being transmitted to applications.

    .PARAMETER SessionId
        Specifies one or more session IDs to examine for buffer contents. Session IDs can be found in sys.dm_exec_sessions or sys.dm_exec_requests.
        Use this when you need to investigate specific sessions that are causing blocking, consuming resources, or exhibiting unusual behavior.
        Cannot be used together with the -All parameter.

    .PARAMETER RequestId
        Specifies the exact request (batch) to examine within a session when multiple requests are active. Optional parameter that defaults to the current request.
        Use this when a session has multiple concurrent requests and you need to examine a specific batch rather than the most recent one.
        Find request IDs by querying sys.dm_exec_requests for the target session_id.

    .PARAMETER All
        Retrieves buffer information for all active user sessions instead of specific session IDs. Excludes system sessions to focus on user activity.
        Use this when performing broad troubleshooting to identify which sessions are running problematic queries or consuming resources.
        This parameter overrides any SessionId or RequestId values and may return large result sets on busy servers.

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
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                $sessionQuery = 'SELECT session_id FROM sys.dm_exec_connections'
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