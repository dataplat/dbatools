function Get-DbaDbccMemoryStatus {
    <#
    .SYNOPSIS
        Executes DBCC MEMORYSTATUS and returns memory usage details in a structured format

    .DESCRIPTION
        Runs DBCC MEMORYSTATUS against SQL Server instances and parses the output into a structured PowerShell object for analysis. This replaces the need to manually execute DBCC MEMORYSTATUS and interpret its raw text output, making memory troubleshooting and monitoring much easier. The function organizes memory statistics by type (like Memory Manager, Buffer Manager, Resource Pool, etc.) and provides both the metric names and values in a consistent format across multiple instances. Useful for diagnosing memory pressure, understanding memory allocation patterns, and comparing memory usage across environments.

        Reference:
            - https://blogs.msdn.microsoft.com/timchapman/2012/08/16/how-to-parse-dbcc-memorystatus-via-powershell/
            - https://support.microsoft.com/en-us/help/907877/how-to-use-the-dbcc-memorystatus-command-to-monitor-memory-usage-on-sq

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC, Memory
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbccMemoryStatus

    .EXAMPLE
        PS C:\> Get-DbaDbccMemoryStatus -SqlInstance sqlcluster, sqlserver2012

        Get output of DBCC MEMORYSTATUS for instances "sqlcluster" and "sqlserver2012". Returns results in a single recordset.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlcluster | Get-DbaDbccMemoryStatus

        Get output of DBCC MEMORYSTATUS for all servers in Server Central Management Server

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        $query = 'DBCC MEMORYSTATUS'
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Collecting $query data from server: $instance"
            try {
                $datatable = $server.query($query, 'master', $true)

                $recordset = 0
                $rowId = 0
                $recordsetId = 0

                foreach ($dataset in $datatable) {
                    $dataSection = $dataset.Columns[0].ColumnName
                    $dataType = $dataset.Columns[1].ColumnName
                    $recordset = $recordset + 1
                    foreach ($row in $dataset.Rows) {
                        $rowId = $rowId + 1
                        $recordsetId = $recordsetId + 1
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            RecordSet    = $RecordSet
                            RowId        = $RowId
                            RecordSetId  = $RecordSetId
                            Type         = $dataSection
                            Name         = $Row[0]
                            Value        = $Row[1]
                            ValueType    = $dataType
                        }
                    }
                    $recordsetId = 0
                }
            } catch {
                Stop-Function -Message "Failure Executing $query" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}