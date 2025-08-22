function Copy-DbaCustomError {
    <#
    .SYNOPSIS
        Migrates custom error messages and their language translations between SQL Server instances

    .DESCRIPTION
        Copies user-defined error messages from the source server's sys.messages system catalog to one or more destination servers. This is essential when migrating applications that rely on custom error numbers and messages, or when standardizing error handling across multiple SQL Server environments.

        Custom errors created with sp_addmessage are automatically discovered and migrated, including all language translations. The English (us_english) version is always created first since SQL Server requires it as the base language before adding translations.

        By default, existing custom errors on the destination are skipped to prevent conflicts. Use -Force to overwrite existing errors. If you drop the English version of a custom error, all language translations for that error ID are automatically dropped as well.

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

    .PARAMETER CustomError
        The custom error(s) to process. This list is auto-populated from the server. If unspecified, all custom errors will be processed.

    .PARAMETER ExcludeCustomError
        The custom error(s) to exclude. This list is auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, the custom error will be dropped and recreated if it already exists on Destination.

    .NOTES
        Tags: Migration, CustomError
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaCustomError

    .EXAMPLE
        PS C:\> Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster

        Copies all server custom errors from sqlserver2014a to sqlcluster using Windows credentials. If custom errors with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaCustomError -Source sqlserver2014a -SourceSqlCredential $scred -Destination sqlcluster -DestinationSqlCredential $dcred -CustomError 60000 -Force

        Copies only the custom error with ID number 60000 from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster -ExcludeCustomError 60000 -Force

        Copies all the custom errors found on sqlserver2014a except the custom error with ID number 60000 to sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$CustomError,
        [object[]]$ExcludeCustomError,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $orderedCustomErrors = @($sourceServer.UserDefinedMessages | Where-Object Language -eq "us_english")
        $orderedCustomErrors += $sourceServer.UserDefinedMessages | Where-Object Language -ne "us_english"

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            # US has to go first
            $destCustomErrors = $destServer.UserDefinedMessages

            foreach ($currentCustomError in $orderedCustomErrors) {
                $customErrorId = $currentCustomError.ID
                $language = $currentCustomError.Language.ToString()

                $copyCustomErrorStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Custom error"
                    Name              = $currentCustomError
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($CustomError -and ($customErrorId -notin $CustomError -or $customErrorId -in $ExcludeCustomError)) {
                    continue
                }

                if ($destCustomErrors.ID -contains $customErrorId) {
                    if ($force -eq $false) {
                        If ($Pscmdlet.ShouldProcess($destinstance, "Custom error $customErrorId $language exists at destination. Use -Force to drop and migrate.")) {
                            $copyCustomErrorStatus.Status = "Skipped"
                            $copyCustomErrorStatus.Notes = "Already exists on destination"
                            $copyCustomErrorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Custom error $customErrorId $language exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        If ($Pscmdlet.ShouldProcess($destinstance, "Dropping custom error $customErrorId $language and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping custom error $customErrorId (drops all languages for custom error $customErrorId)"
                                $destServer.UserDefinedMessages[$customErrorId, $language].Drop()
                            } catch {
                                $copyCustomErrorStatus.Status = "Failed"
                                $copyCustomErrorStatus.Notes = "$PSItem"
                                $copyCustomErrorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping custom error $customErrorId $language on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating custom error $customErrorId $language")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying custom error $customErrorId $language"
                        $sql = $currentCustomError.Script() | Out-String
                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql)
                        $copyCustomErrorStatus.Status = "Successful"
                        $copyCustomErrorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyCustomErrorStatus.Status = "Failed"
                        $copyCustomErrorStatus.Notes = "$PSItem"
                        $copyCustomErrorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating custom error $customErrorId $language on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}