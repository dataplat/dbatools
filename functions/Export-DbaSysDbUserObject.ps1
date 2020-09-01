function Export-DbaSysDbUserObject {
    <#
    .SYNOPSIS
        Exports all user objects found in source SQL Server's master, msdb and model databases to the FilePath.

    .DESCRIPTION
        Exports all user objects found in source SQL Server's master, msdb and model databases to the FilePath.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.
        This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials.
        Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER IncludeDependencies
        Specifies whether dependent objects are also scripted out.

    .PARAMETER BatchSeparator
        Batch separator for scripting output. "GO" by default.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER NoPrefix
        If this switch is used, the scripts will not include prefix information containing creator and datetime.

    .PARAMETER ScriptingOptionsObject
        Add scripting options to scripting output.

    .PARAMETER NoClobber
        Do not overwrite file.

    .PARAMETER Passthru
        Output script to console.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        PS> Export-DbaSysDbUserObject -SqlInstance server1

        Exports any user objects that are in the system database to the default location.

    .NOTES
    General notes

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
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
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
                        if (!(Test-Bound -ParameterName ScriptingOption)) {
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