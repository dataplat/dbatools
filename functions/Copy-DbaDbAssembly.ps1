function Copy-DbaDbAssembly {
    <#
    .SYNOPSIS
        Copy-DbaDbAssembly migrates assemblies from one SQL Server to another.

    .DESCRIPTION
        By default, all assemblies are copied.

        If the assembly already exists on the destination, it will be skipped unless -Force is used.

        This script does not yet copy dependencies or dependent objects.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Assembly
        The assembly(ies) to process. This list is auto-populated from the server. If unspecified, all assemblies will be processed.

    .PARAMETER ExcludeAssembly
        The assembly(ies) to exclude. This list is auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing assemblies on Destination with matching names from Source will be dropped.

    .NOTES
        Tags: Migration, Assembly
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaDbAssembly

    .EXAMPLE
        PS C:\> Copy-DbaDbAssembly -Source sqlserver2014a -Destination sqlcluster

        Copies all assemblies from sqlserver2014a to sqlcluster using Windows credentials. If assemblies with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaDbAssembly -Source sqlserver2014a -Destination sqlcluster -Assembly dbname.assemblyname, dbname3.anotherassembly -SourceSqlCredential $cred -Force

        Copies two assemblies, the dbname.assemblyname and dbname3.anotherassembly from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an assembly with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

        In this example, anotherassembly will be copied to the dbname3 database on the server sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaDbAssembly -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Assembly,
        [object[]]$ExcludeAssembly,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $sourceAssemblies = @()
        foreach ($database in ($sourceServer.Databases | Where-Object IsAccessible)) {
            Write-Message -Level Verbose -Message "Processing $database on source"

            try {
                # a bug here requires a try/catch
                $userAssemblies = $database.Assemblies | Where-Object IsSystemObject -eq $false
                foreach ($assembly in $userAssemblies) {
                    $sourceAssemblies += $assembly
                }
            } catch {
                #here to avoid an empty catch
                $null = 1
            }
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            $destAssemblies = @()
            foreach ($database in $destServer.Databases) {
                Write-Message -Level VeryVerbose -Message "Processing $database on destination"
                try {
                    # a bug here requires a try/catch
                    $userAssemblies = $database.Assemblies | Where-Object IsSystemObject -eq $false
                    foreach ($assembly in $userAssemblies) {
                        $destAssemblies += $assembly
                    }
                } catch {
                    #here to avoid an empty catch
                    $null = 1
                }
            }
            foreach ($currentAssembly in $sourceAssemblies) {
                $assemblyName = $currentAssembly.Name
                $dbName = $currentAssembly.Parent.Name
                $destDb = $destServer.Databases[$dbName]
                Write-Message -Level VeryVerbose -Message "Processing $assemblyName on $dbname"
                $copyDbAssemblyStatus = [pscustomobject]@{
                    SourceServer        = $sourceServer.Name
                    SourceDatabase      = $dbName
                    DestinationServer   = $destServer.Name
                    DestinationDatabase = $destDb
                    type                = "Database Assembly"
                    Name                = $assemblyName
                    Status              = $null
                    Notes               = $null
                    DateTime            = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }


                if (!$destDb) {
                    $copyDbAssemblyStatus.Status = "Skipped"
                    $copyDbAssemblyStatus.Notes = "Destination database does not exist"
                    $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Write-Message -Level Verbose -Message "Destination database $dbName does not exist. Skipping $assemblyName.";
                    continue
                }

                if ((Test-Bound -ParameterName Assembly) -and $Assembly -notcontains "$dbName.$assemblyName" -or $ExcludeAssembly -contains "$dbName.$assemblyName") {
                    continue
                }

                if ($currentAssembly.AssemblySecurityLevel -eq "External" -and -not $destDb.Trustworthy) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Setting $dbName to External")) {
                        Write-Message -Level Verbose -Message "Setting $dbName Security Level to External on $destinstance."
                        $sql = "ALTER DATABASE $dbName SET TRUSTWORTHY ON"
                        try {
                            Write-Message -Level Debug -Message $sql
                            $destServer.Query($sql)
                        } catch {
                            $copyDbAssemblyStatus.Status = "Failed"
                            $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue setting security level." -Target $destDb -ErrorRecord $_
                        }
                    }
                }

                if ($destServer.Databases[$dbName].Assemblies.Name -contains $currentAssembly.name) {
                    if ($force -eq $false) {
                        $copyDbAssemblyStatus.Status = "Skipped"
                        $copyDbAssemblyStatus.Notes = "Already exists on destination"
                        $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Write-Message -Level Verbose -Message "Assembly $assemblyName exists at destination in the $dbName database. Use -Force to drop and migrate."
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping assembly $assemblyName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping assembly $assemblyName."
                                Write-Message -Level Verbose -Message "This won't work if there are dependencies."
                                $destServer.Databases[$dbName].Assemblies[$assemblyName].Drop()
                                Write-Message -Level Verbose -Message "Copying assembly $assemblyName."
                                $sql = $currentAssembly.Script()
                                Write-Message -Level Debug -Message $sql
                                $destServer.Query($sql, $dbName)
                            } catch {
                                $copyDbAssemblyStatus.Status = "Failed"
                                $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Stop-Function -Message "Issue dropping assembly." -Target $assemblyName -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating assembly $assemblyName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying assembly $assemblyName from database."
                        $sql = $currentAssembly.Script()
                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql, $dbName)

                        $copyDbAssemblyStatus.Status = "Successful"
                        $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    } catch {
                        $copyDbAssemblyStatus.Status = "Failed"
                        $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue creating assembly." -Target $assemblyName -ErrorRecord $_
                    }
                }
            }
        }
    }
}