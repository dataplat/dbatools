function Get-DbaDbView {
    <#
    .SYNOPSIS
        Retrieves SQL Server database views with metadata for documentation and analysis.

    .DESCRIPTION
        Retrieves all database views from SQL Server instances along with their schema, creation dates, and modification timestamps. This helps DBAs document database architecture, analyze view dependencies, and audit database objects across multiple servers and databases. The function excludes system views by default when requested, making it useful for focusing on custom business logic views.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        To get views from specific database(s) - this list is auto populated from the server.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto populated from the server.

    .PARAMETER ExcludeSystemView
        This switch removes all system objects from the view collection.

    .PARAMETER View
        The view(s) to include - all views are selected if not populated

    .PARAMETER Schema
        Only return views from the specified schema

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: View, Database
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbView

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance sql2016

        Gets all database views

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance Server1 -Database db1

        Gets the views for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance Server1 -ExcludeDatabase db1

        Gets the views for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance Server1 -ExcludeSystemView

        Gets the views for all databases that are not system objects (there can be 400+ system views in each DB)

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbView

        Gets the views for the databases on Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance Server1 -ExcludeSystem | Get-DbaDbView

        Pipe the databases from Get-DbaDatabase into Get-DbaDbView

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance Server1 -Database db1 -View vw1

        Gets the view vw1 for the db1 database

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemView,
        [string[]]$View,
        [string[]]$Schema,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($View) {
            $fqtns = @()
            foreach ($v in $View) {
                $fqtn = Get-ObjectNameParts -ObjectName $v

                if (-not $fqtn.Parsed) {
                    Write-Message -Level Warning -Message "Please check you are using proper three-part names. If your search value contains special characters you must use [ ] to wrap the name. The value $t could not be parsed as a valid name."
                    Continue
                }

                $fqtns += [PSCustomObject] @{
                    Database   = $fqtn.Database
                    Schema     = $fqtn.Schema
                    View       = $fqtn.Name
                    InputValue = $fqtn.InputValue
                }
            }
            if (-not $fqtns) {
                Stop-Function -Message "No Valid View specified"
                return
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if (Test-Bound SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            Write-Message -Level Verbose -Message "processing $db"

            # Let the SMO read all properties referenced in this command for all views in the database in one query.
            # Downside: If some other properties were already read outside of this command in the used SMO, they are cleared.
            $db.Views.ClearAndInitialize('', [string[]]('Name', 'Schema', 'IsSystemObject', 'CreateDate', 'DateLastModified'))

            if ($fqtns) {
                $views = @()
                foreach ($fqtn in $fqtns) {
                    # If the user specified a database in a three-part name, and it's not the
                    # database currently being processed, skip this view.
                    if ($fqtn.Database) {
                        if ($fqtn.Database -ne $db.Name) {
                            continue
                        }
                    }

                    $vw = $db.Views | Where-Object { $_.Name -in $fqtn.View -and $fqtn.Schema -in ($_.Schema, $null) -and $fqtn.Database -in ($_.Parent.Name, $null) }

                    if (-not $vw) {
                        Write-Message -Level Verbose -Message "Could not find view $($fqtn.View) in $db on $($db.Parent.DomainInstanceName)"
                    }
                    $views += $vw
                }
            } else {
                $views = $db.Views
            }

            if (-not $db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping"
                continue
            }

            if (-not $views) {
                Write-Message -Message "No views exist in the $db database on $($db.Parent.DomainInstanceName)" -Target $db -Level Verbose
                continue
            }

            if ($Schema) {
                $views = $views | Where-Object Schema -in $Schema
            }

            if (Test-Bound -ParameterName ExcludeSystemView) {
                $views = $views | Where-Object { -not $_.IsSystemObject }
            }

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'CreateDate', 'DateLastModified', 'Name'
            foreach ($sqlview in $views) {

                Add-Member -Force -InputObject $sqlview -MemberType NoteProperty -Name ComputerName -Value $db.Parent.ComputerName
                Add-Member -Force -InputObject $sqlview -MemberType NoteProperty -Name InstanceName -Value $db.Parent.ServiceName
                Add-Member -Force -InputObject $sqlview -MemberType NoteProperty -Name SqlInstance -Value $db.Parent.DomainInstanceName
                Add-Member -Force -InputObject $sqlview -MemberType NoteProperty -Name Database -Value $db.Name

                Select-DefaultView -InputObject $sqlview -Property $defaults
            }
        }
    }
}