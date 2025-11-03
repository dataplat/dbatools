function Export-DbaSysDbUserObject {
    <#
    .SYNOPSIS
        Discovers and exports user-created objects from SQL Server system databases (master, model, msdb) to SQL script files.

    .DESCRIPTION
        Scans the master, model, and msdb system databases to identify tables, views, stored procedures, functions, triggers, and other objects that were created by users rather than SQL Server itself. This function helps DBAs document custom objects that may have been inadvertently created in system databases, which is critical for server migrations, compliance audits, and maintaining clean system database environments. The exported SQL scripts can be used to recreate these objects on other instances or to review what custom code exists in your system databases.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.
        This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials.
        Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER IncludeDependencies
        Includes dependent objects in the scripted output when exporting user objects.
        Use this when your custom objects have dependencies that need to be recreated together on the target instance.

    .PARAMETER BatchSeparator
        Sets the batch separator used between SQL statements in the exported script files. Defaults to "GO".
        Change this when you need compatibility with specific SQL tools that use different batch separators.

    .PARAMETER Path
        Specifies the directory where the exported SQL script file will be created. Uses the dbatools default export path if not specified.
        Provide this when you need the script saved to a specific location for documentation or deployment purposes.

    .PARAMETER FilePath
        Specifies the complete file path including filename for the exported SQL script.
        Use this instead of Path when you need precise control over the output file name and location.

    .PARAMETER NoPrefix
        Excludes header information from the exported scripts, removing creator details and timestamp comments.
        Use this when you need clean scripts without metadata for version control or when the header information is not needed.

    .PARAMETER ScriptingOptionsObject
        Provides a custom ScriptingOptions object to control how objects are scripted, including permissions, indexes, and constraints.
        Use this when you need specific scripting behavior beyond the default options, such as excluding certain object properties.

    .PARAMETER NoClobber
        Prevents overwriting existing files at the target location and throws an error if the file already exists.
        Use this as a safety measure when you want to avoid accidentally replacing existing script files.

    .PARAMETER PassThru
        Outputs the generated SQL scripts directly to the PowerShell console instead of saving to a file.
        Use this when you want to review the scripts immediately or pipe them to other cmdlets for further processing.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        PS C:\> Export-DbaSysDbUserObject -SqlInstance server1

        Exports any user objects that are in the system database to the default location.

    .NOTES
        Tags: Export, Object, SystemDatabase
        Author: Jess Pomfret (@jpomfret)

        Website: https://dbatools.io
        Copyright: (c) 2019 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaSysDbUserObject
    #>

    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$IncludeDependencies = $false,
        [string]$BatchSeparator = 'GO',
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [string]$FilePath,
        [switch]$NoPrefix,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject,
        [switch]$NoClobber,
        [switch]$PassThru,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Attempting to connect to $instance"
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                if (!(Test-SqlSa -SqlInstance $server -SqlCredential $SqlCredential)) {
                    Stop-Function -Message "Not a sysadmin on $instance. Quitting."
                    return
                }
                $scriptPath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $SessionObject.Instance

                $systemDbs = "master", "model", "msdb"

                foreach ($systemDb in $systemDbs) {
                    $smoDb = $server.databases[$systemDb]
                    $userObjects = @()
                    $userObjects += $smoDb.Tables | Where-Object IsSystemObject -ne $true | Select-Object Name, @{l = 'SchemaName'; e = { $_.Schema } } , @{l = 'Type'; e = { 'TABLE' } }, @{l = 'Database'; e = { $systemDb } }
                    $userObjects += $smoDb.Triggers | Where-Object IsSystemObject -ne $true | Select-Object Name, @{l = 'SchemaName'; e = { $null } } , @{l = 'Type'; e = { 'SQL_TRIGGER' } }, @{l = 'Database'; e = { $systemDb } }
                    $params = @{
                        SqlInstance          = $server
                        Database             = $systemDb
                        ExcludeSystemObjects = $true
                        Type                 = 'View', 'TableValuedFunction', 'DefaultConstraint', 'StoredProcedure', 'Rule', 'InlineTableValuedFunction', 'ScalarFunction'
                    }
                    $userObjects += Get-DbaModule @params | Sort-Object Type | Select-Object Name, SchemaName, Type, Database

                    if ($userObjects) {
                        $results = @()
                        foreach ($userObject in $userObjects) {
                            $smObject = switch ($userObject.Type) {
                                "TABLE" { $smoDb.Tables.Item($userObject.Name, $userObject.SchemaName) }
                                "VIEW" { $smoDb.Views.Item($userObject.Name, $userObject.SchemaName) }
                                "SQL_STORED_PROCEDURE" { $smoDb.StoredProcedures.Item($userObject.Name, $userObject.SchemaName) }
                                "RULE" { $smoDb.Rules.Item($userObject.Name, $userObject.SchemaName) }
                                "SQL_TRIGGER" { $smoDb.Triggers.Item($userObject.Name) }
                                "SQL_TABLE_VALUED_FUNCTION" { $smoDb.UserDefinedFunctions.Item($userObject.Name, $userObject.SchemaName) }
                                "SQL_INLINE_TABLE_VALUED_FUNCTION" { $smoDb.UserDefinedFunctions.Item($userObject.Name, $userObject.SchemaName) }
                                "SQL_SCALAR_FUNCTION" { $smoDb.UserDefinedFunctions.Item($userObject.Name, $userObject.SchemaName) }
                            }
                            $results += $smObject
                        }

                        if ((Test-Path -Path $scriptPath) -and $NoClobber) {
                            Stop-Function -Message "File already exists. If you want to overwrite it remove the -NoClobber parameter. If you want to append data, please Use -Append parameter." -Target $scriptPath -Continue
                        }
                        if (!(Test-Bound -ParameterName ScriptingOptionsObject)) {
                            $ScriptingOptionsObject = New-DbaScriptingOption
                            $ScriptingOptionsObject.IncludeDatabaseContext = $true
                            $ScriptingOptionsObject.ScriptBatchTerminator = $true
                            $ScriptingOptionsObject.AnsiFile = $true
                            if ($IncludeDependencies) {
                                $ScriptingOptionsObject.WithDependencies = $true
                            }
                        }

                        $export = @{
                            NoPrefix         = $NoPrefix
                            ScriptingOptions = $ScriptingOptionsObject
                            BatchSeparator   = $BatchSeparator
                        }

                        if ($PassThru) {
                            $results | Export-DbaScript @export -PassThru
                        } elseif ($Path -Or $FilePath) {
                            $results | Export-DbaScript @export -FilePath $scriptPath -Append -NoClobber:$NoClobber
                        }
                    }
                }
            } catch {
                Stop-Function -Message ("Exporting system objects failed on '{0}'" -f $server.Name)
            }
        }
    }
}