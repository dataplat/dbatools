function Invoke-DbaDbDbccCleanTable {
    <#
    .SYNOPSIS
        Reclaims disk space from dropped variable-length columns in tables and indexed views

    .DESCRIPTION
        Executes DBCC CLEANTABLE to reclaim disk space after variable-length columns (varchar, nvarchar, varbinary, text, ntext, image, xml, or CLR user-defined types) have been dropped from tables or indexed views.

        When you drop variable-length columns, SQL Server doesn't immediately reclaim the space those columns occupied. This function runs the necessary DBCC command to physically remove that unused space and compact the remaining data, which can significantly reduce table size and improve performance.

        The function accepts either table names (like 'dbo.TableName') or table object IDs for processing. You can control the operation through batch processing to minimize impact on production systems, and optionally suppress informational messages for cleaner output.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-cleantable-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to include in the clean table operation. Accepts multiple database names.
        When omitted, the operation runs against all accessible databases on the instance.
        Use this to target specific databases where you know variable-length columns have been dropped recently.

    .PARAMETER Object
        Specifies the table or indexed view names to clean, or their object IDs for more precise targeting.
        Accepts schema-qualified names like 'dbo.TableName' or numeric object IDs like 34636372.
        This parameter is required since DBCC CLEANTABLE must target specific objects, not entire databases.

    .PARAMETER BatchSize
        Controls how many rows are processed per transaction during the clean operation.
        Use smaller batch sizes (like 5000-10000) on production systems to reduce lock duration and transaction log impact.
        When omitted, processes the entire table in a single transaction which is faster but holds locks longer.

    .PARAMETER NoInformationalMessages
        Suppresses informational messages from the DBCC CLEANTABLE output, showing only errors and warnings.
        Use this in automated scripts or when processing multiple tables to reduce console output volume.
        Equivalent to adding WITH NO_INFOMSGS to the DBCC command.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

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
        https://dbatools.io/Invoke-DbaDbDbccCleanTable

    .OUTPUTS
        PSCustomObject

        Returns one object per table or indexed view being cleaned across all specified databases.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: Name of the database containing the object being cleaned
        - Object: The table or indexed view name or object ID specified for cleaning
        - Cmd: The DBCC CLEANTABLE command that was executed
        - Output: DBCC output messages, informational status, or null if operation completed silently

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCleanTable -SqlInstance SqlServer2017 -Database CurrentDB -Object 'dbo.SomeTable'

        Connects to CurrentDB on instance SqlServer2017 using Windows Authentication and runs the command DBCC CLEANTABLE('CurrentDB', 'dbo.SomeTable') to reclaim space after variable-length columns have been dropped.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccCleanTable -SqlInstance SqlServer2017 -Database CurrentDB -Object 34636372 -BatchSize 5000

        Connects to CurrentDB on instance SqlServer2017 using Windows Authentication and runs the command DBCC CLEANTABLE('CurrentDB', 34636372, 5000) to reclaim space from table with Table_Id = 34636372 after variable-length columns have been dropped.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Invoke-DbaDbDbccCleanTable -SqlInstance SqlServer2017 -SqlCredential $cred -Database CurrentDB -Object 'dbo.SomeTable'  -NoInformationalMessages

        Connects to CurrentDB on instance SqlServer2017 using sqladmin credential and runs the command DBCC CLEANTABLE('CurrentDB', 'dbo.SomeTable') WITH NO_INFOMSGS to reclaim space after variable-length columns have been dropped.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Invoke-DbaDbDbccCleanTable -Object 'dbo.SomeTable' -BatchSize 5000

        Runs the command DBCC CLEANTABLE('DatabaseName', 'dbo.SomeTable', 5000) against all databases on Sql1 and Sql2/sqlexpress.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Object,
        [int]$BatchSize,
        [switch]$NoInformationalMessages,
        [switch]$EnableException
    )
    begin {
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC CLEANTABLE(#options#)")
        if (Test-Bound -ParameterName NoInformationalMessages) {
            $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
        }
    }
    process {
        if (Test-Bound -Not -ParameterName Object) {
            Stop-Function -Message "You must specify a table or indexed view to execute against using -Object"
            return
        }
        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping." -Continue
                }

                foreach ($obj in $Object) {
                    try {
                        $query = $StringBuilder.ToString()
                        $options = New-Object System.Text.StringBuilder
                        if ($obj -match '^\d+$') {
                            $null = $options.Append("'$($db.Name)', $($obj)")
                        } else {
                            $null = $options.Append("'$($db.Name)', '$($obj)'")
                        }
                        if (Test-Bound -ParameterName BatchSize) {
                            $null = $options.Append(", $($BatchSize)")
                        }

                        $query = $query.Replace('#options#', "$($options.ToString())")
                        Write-Message -Message "Query to run: $query" -Level Verbose

                        if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                            Write-Message -Message "Query to run: $query" -Level Verbose
                            $results = $server | Invoke-DbaQuery  -Query $query -Database $db.Name -MessagesToOutput
                        }
                    } catch {
                        Stop-Function -Message "Error running  $query against $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue
                    }
                    if ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                        if (($null -eq $results) -or ($results.GetType().Name -eq 'String') ) {
                            [PSCustomObject]@{
                                ComputerName = $server.ComputerName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $db.Name
                                Object       = $obj
                                Cmd          = $query.ToString()
                                Output       = $results
                            }
                        }
                    }
                }
            }
        }
    }
}