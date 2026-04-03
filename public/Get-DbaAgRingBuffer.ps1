function Get-DbaAgRingBuffer {
    <#
    .SYNOPSIS
        Retrieves Always On availability group diagnostic data from SQL Server's internal HADR ring buffers.

    .DESCRIPTION
        This command queries sys.dm_os_ring_buffers for HADR-specific ring buffer types to provide diagnostic
        information about Always On availability groups. These ring buffers record state transitions, role changes,
        commit activity, and transport state events useful for troubleshooting AG health and failover issues.

        As noted in Microsoft's documentation, the ring buffers are not officially supported, but they provide
        valuable post-mortem diagnostic data, especially when SQL Server stops responding or has crashed.

        Reference: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-ring-buffers

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. To use:
        $cred = Get-Credential, this pass this $cred to the param.

        Windows Authentication will be used if SqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER RingBufferType
        Specifies which HADR ring buffer types to query. Defaults to all four HADR ring buffer types.

        Valid values:
        - RING_BUFFER_HADRDBMGR_API       : State transitions at the API level
        - RING_BUFFER_HADRDBMGR_STATE     : Database manager state change records
        - RING_BUFFER_HADRDBMGR_COMMIT    : Commit-level activity records
        - RING_BUFFER_HADR_TRANSPORT_STATE: Connection and transport state transitions

    .PARAMETER CollectionMinutes
        Specifies how many minutes of historical data to retrieve from the ring buffer. Defaults to 60 minutes.
        Use this to extend the analysis window when investigating longer-term AG issues or to focus on recent activity with shorter periods.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per ring buffer record retrieved from the SQL Server instance.

        Properties:
        - ComputerName    : The computer name of the SQL Server instance
        - InstanceName    : The SQL Server instance name
        - SqlInstance     : The full SQL Server instance name (computer\instance)
        - RingBufferType  : The type of ring buffer (e.g. RING_BUFFER_HADRDBMGR_API)
        - RecordId        : The unique record identifier from the ring buffer entry
        - EventTime       : Approximate DateTime of the event (in local server time)
        - Record          : The raw XML record containing event-specific diagnostic fields

    .NOTES
        Tags: Diagnostic, Buffer, HADR, AvailabilityGroup, AG, AlwaysOn
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgRingBuffer

    .EXAMPLE
        PS C:\> Get-DbaAgRingBuffer -SqlInstance sql2019

        Returns HADR ring buffer records from the last 60 minutes from the sql2019 instance.

    .EXAMPLE
        PS C:\> Get-DbaAgRingBuffer -SqlInstance sql2019 -CollectionMinutes 240

        Returns HADR ring buffer records from the last 240 minutes from the sql2019 instance.

    .EXAMPLE
        PS C:\> Get-DbaAgRingBuffer -SqlInstance sql2019 -RingBufferType RING_BUFFER_HADRDBMGR_API

        Returns only RING_BUFFER_HADRDBMGR_API records from the last 60 minutes from the sql2019 instance.

    .EXAMPLE
        PS C:\> Get-DbaAgRingBuffer -SqlInstance sql2019 -RingBufferType RING_BUFFER_HADRDBMGR_API, RING_BUFFER_HADR_TRANSPORT_STATE

        Returns API and transport state records from sql2019.

    .EXAMPLE
        PS C:\> 'sql2019', 'sql2022' | Get-DbaAgRingBuffer

        Returns all HADR ring buffer records from sql2019 and sql2022.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("RING_BUFFER_HADRDBMGR_API", "RING_BUFFER_HADRDBMGR_STATE", "RING_BUFFER_HADRDBMGR_COMMIT", "RING_BUFFER_HADR_TRANSPORT_STATE")]
        [string[]]$RingBufferType,
        [int]$CollectionMinutes = 60,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $currentTimestamp = ($server.Query("SELECT cpu_ticks / CONVERT(FLOAT, (cpu_ticks / ms_ticks)) AS TimeStamp FROM sys.dm_os_sys_info"))[0]
            Write-Message -Level Verbose -Message "Using current timestamp of $currentTimestamp"

            if ($RingBufferType) {
                $typeList = ($RingBufferType | ForEach-Object { "N'$_'" }) -join ", "
            } else {
                $typeList = "N'RING_BUFFER_HADRDBMGR_API', N'RING_BUFFER_HADRDBMGR_STATE', N'RING_BUFFER_HADRDBMGR_COMMIT', N'RING_BUFFER_HADR_TRANSPORT_STATE'"
            }

            $sql = "WITH HadrRingBuffer AS
                (
                    SELECT
                        ring_buffer_type,
                        timestamp,
                        CONVERT(XML, record) AS record
                    FROM sys.dm_os_ring_buffers
                    WHERE ring_buffer_type IN ($typeList)
                )
                SELECT
                    SERVERPROPERTY('ServerName') AS ServerName,
                    ring_buffer_type,
                    record.value('(./Record/@id)[1]', 'int') AS record_id,
                    DATEADD(ms, -1 * ($currentTimestamp - [timestamp]), GETDATE()) AS EventTime,
                    record
                FROM HadrRingBuffer
                WHERE DATEADD(ms, -1 * ($currentTimestamp - [timestamp]), GETDATE()) > DATEADD(MINUTE, -$CollectionMinutes, GETDATE())
                ORDER BY EventTime DESC;"

            Write-Message -Level Verbose -Message "Executing SQL Statement: $sql"
            foreach ($row in $server.Query($sql)) {
                [PSCustomObject]@{
                    ComputerName   = $server.ComputerName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    RingBufferType = $row.ring_buffer_type
                    RecordId       = $row.record_id
                    EventTime      = $row.EventTime
                    Record         = $row.record
                }
            }
        }
    }
}
