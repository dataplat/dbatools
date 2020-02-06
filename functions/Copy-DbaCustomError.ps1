function Copy-DbaCustomError {
    <#
    .SYNOPSIS
        Copy-DbaCustomError migrates custom errors (user defined messages), by the custom error ID, from one SQL Server to another.

    .DESCRIPTION
        By default, all custom errors are copied. The -CustomError parameter is auto-populated for command-line completion and can be used to copy only specific custom errors.

        If the custom error already exists on the destination, it will be skipped unless -Force is used. The us_english version must be created first. If you drop the us_english version, all the other languages will be dropped for that specific ID as well.

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
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
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
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            # US has to go first
            $destCustomErrors = $destServer.UserDefinedMessages

            foreach ($currentCustomError in $orderedCustomErrors) {
                $customErrorId = $currentCustomError.ID
                $language = $currentCustomError.Language.ToString()

                $copyCustomErrorStatus = [pscustomobject]@{
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
                        $copyCustomErrorStatus.Status = "Skipped"
                        $copyCustomErrorStatus.Notes = "Already exists on destination"
                        $copyCustomErrorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Write-Message -Level Verbose -Message "Custom error $customErrorId $language exists at destination. Use -Force to drop and migrate."
                        continue
                    } else {
                        If ($Pscmdlet.ShouldProcess($destinstance, "Dropping custom error $customErrorId $language and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping custom error $customErrorId (drops all languages for custom error $customErrorId)"
                                $destServer.UserDefinedMessages[$customErrorId, $language].Drop()
                            } catch {
                                $copyCustomErrorStatus.Status = "Failed"
                                $copyCustomErrorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Stop-Function -Message "Issue dropping custom error" -Target $customErrorId -ErrorRecord $_ -Continue
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
                        $copyCustomErrorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue creating custom error" -Target $customErrorId -ErrorRecord $_
                    }
                }
            }
        }
    }
}