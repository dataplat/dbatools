function Get-DbaStartupProcedure {
    <#
    .SYNOPSIS
        Retrieves stored procedures configured to run automatically when SQL Server starts up.

    .DESCRIPTION
        This function returns stored procedures from the master database that are configured to execute automatically during SQL Server startup. Startup procedures are useful for initializing application settings, populating cache tables, or performing other tasks that need to run every time the SQL Server service starts. The function returns SMO StoredProcedure objects with details about each startup procedure, including creation dates, schemas, and implementation types. You can filter results to check if specific procedures are configured as startup procedures, which is helpful for auditing server configurations or troubleshooting startup issues.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER StartupProcedure
        Filters results to check if specific stored procedures are configured as startup procedures. Accepts procedure names in 'schema.procedurename' format or just 'procedurename' for dbo schema.
        Use this when auditing server configurations or verifying that critical initialization procedures are properly configured to run at startup.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Procedure, Startup, StartupProcedure
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.StoredProcedure

        Returns one StoredProcedure object for each stored procedure configured as a startup procedure in the master database. Connection context properties are added via NoteProperty.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Database name containing the stored procedure (always "master" for startup procedures)
        - Schema: The schema name containing the stored procedure
        - ObjectId: The object ID of the stored procedure within SQL Server
        - CreateDate: DateTime when the stored procedure was created
        - DateLastModified: DateTime when the stored procedure was last modified
        - Name: The name of the stored procedure
        - ImplementationType: The implementation type of the procedure (T-SQL or CLR)
        - Startup: Boolean indicating if the procedure is configured as a startup procedure

        Additional properties available from the SMO StoredProcedure object (use Select-Object *):
        - Parent: Reference to the parent database object
        - Owner: The principal that owns the stored procedure
        - ExecutionContext: Execution context (Caller or Owner)
        - IsEncrypted: Boolean indicating if the procedure is encrypted
        - IsRecompiled: Boolean indicating if the procedure is recompiled on execution
        - IsSystemObject: Boolean indicating if this is a system object
        - Urn: The Unified Resource Name for the object
        - State: The current state of the SMO object (Existing, Creating, Pending, etc.)

    .LINK
        https://dbatools.io/Get-DbaStartupProcedure

    .EXAMPLE
        PS C:\> Get-DbaStartupProcedure -SqlInstance SqlBox1\Instance2

        Returns an object with all startup procedures for the Instance2 instance on SqlBox1

    .EXAMPLE
        PS C:\> Get-DbaStartupProcedure -SqlInstance SqlBox1\Instance2 -StartupProcedure 'dbo.StartupProc'

        Returns an object with a startup procedure named 'dbo.StartupProc' for the Instance2 instance on SqlBox1

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Get-DbaStartupProcedure

        Returns an object with all startup procedures for every server listed in the Central Management Server on sql2014

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$StartupProcedure,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Getting startup procedures for $servername"

            $startupProcs = $server.EnumStartupProcedures()

            if ($startupProcs.Rows.Count -gt 0) {
                $db = $server.Databases['master']
                foreach ($startupProc in $startupProcs) {
                    if (Test-Bound -ParameterName StartupProcedure) {
                        $returnProc = $false
                        foreach ($proc in $StartupProcedure) {
                            $procParts = Get-ObjectNameParts $proc
                            if (-not $procParts.Parsed) {
                                Write-Message -Level Verbose -Message "Requested procedure $proc could not be parsed."
                                Continue
                            }
                            if (($procParts.Name -eq $startupProc.Name) -and ($procParts.Schema -eq $startupProc.Schema)) {
                                $returnProc = $true
                                Break
                            }
                        }

                    } else {
                        $returnProc = $true
                    }
                    if (!$returnProc) {
                        Continue
                    }
                    $proc = $db.StoredProcedures.Item($startupProc.Name, $startupProc.Schema)

                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name Database -value $db.Name

                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'ID as ObjectId', 'CreateDate',
                    'DateLastModified', 'Name', 'ImplementationType', 'Startup'
                    Select-DefaultView -InputObject $proc -Property $defaults
                }
            }
        }
    }
}