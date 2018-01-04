function Copy-DbaDatabaseMail {
    <#
    .SYNOPSIS
        Migrates Mail Profiles, Accounts, Mail Servers and Mail Server Configs from one SQL Server to another.

    .DESCRIPTION
        By default, all mail configurations for Profiles, Accounts, Mail Servers and Configs are copied.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

        $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

        Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

        To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

        $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

        Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

        To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER Type
        Specifies the object type to migrate. Valid options are "Job", "Alert" and "Operator". When Type is specified, all categories from the selected type will be migrated.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing objects on Destination with matching names from Source will be dropped.

    .NOTES
        Tags: Migration, Mail
        Author: Chrissy LeMaire (@cl), netnerds.net
        Requires: sysadmin access on SQL Servers

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Copy-DbaDatabaseMail

    .EXAMPLE
        Copy-DbaDatabaseMail -Source sqlserver2014a -Destination sqlcluster

        Copies all database mail objects from sqlserver2014a to sqlcluster using Windows credentials. If database mail objects with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        Copy-DbaDatabaseMail -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all database mail objects from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

    .EXAMPLE
        Copy-DbaDatabaseMail -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    .EXAMPLE
        Copy-DbaDatabaseMail -Source sqlserver2014a -Destination sqlcluster -EnableException

        Performs execution of function, and will throw a terminating exception if something breaks
    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [Parameter(ParameterSetName = 'SpecificTypes')]
        [ValidateSet('ConfigurationValues', 'Profiles', 'Accounts', 'mailServers')]
        [string[]]$Type,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        function Copy-DbaDatabaseMailConfig {
            [cmdletbinding(SupportsShouldProcess = $true)]
            param ()

            Write-Message -Message "Migrating mail server configuration values." -Level Verbose
            $copyMailConfigStatus = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = "Server Configuration"
                Type              = "Mail Configuration"
                Status            = $null
                Notes             = $null
                DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
            }
            if ($pscmdlet.ShouldProcess($destination, "Migrating all mail server configuration values.")) {
                try {
                    $sql = $mail.ConfigurationValues.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                    Write-Message -Message $sql -Level Debug
                    $destServer.Query($sql) | Out-Null
                    $mail.ConfigurationValues.Refresh()
                    $copyMailConfigStatus.Status = "Successful"
                }
                catch {
                    $copyMailConfigStatus.Status = "Failed"
                    $copyMailConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Stop-Function -Message "Unable to migrate mail configuration." -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
                }
            }
            $copyMailConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
        }

        function Copy-DbaDatabaseAccount {
            $sourceAccounts = $sourceServer.Mail.Accounts
            $destAccounts = $destServer.Mail.Accounts

            Write-Message -Message "Migrating accounts." -Level Verbose
            foreach ($account in $sourceAccounts) {
                $accountName = $account.name
                $copyMailAccountStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $accountName
                    Type              = "Mail Account"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($accounts.count -gt 0 -and $accounts -notcontains $accountName) {
                    continue
                }

                if ($destAccounts.name -contains $accountName) {
                    if ($force -eq $false) {
                        $copyMailAccountStatus.Status = "Skipped"
                        $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Message "Account $accountName exists at destination. Use -Force to drop and migrate." -Level Verbose
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destination, "Dropping account $accountName and recreating.")) {
                        try {
                            Write-Message -Message "Dropping account $accountName." -Level Verbose
                            $destServer.Mail.Accounts[$accountName].Drop()
                            $destServer.Mail.Accounts.Refresh()
                        }
                        catch {
                            $copyMailAccountStatus.Status = "Failed"
                            $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue dropping account." -Target $accountName -Category InvalidOperation -InnerErrorRecord $_ -Continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destination, "Migrating account $accountName.")) {
                    try {
                        Write-Message -Message "Copying mail account $accountName." -Level Verbose
                        $sql = $account.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $copyMailAccountStatus.Status = "Successful"
                    }
                    catch {
                        $copyMailAccountStatus.Status = "Failed"
                        $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue copying mail account." -Target $accountName -Category InvalidOperation -InnerErrorRecord $_
                    }
                }
                $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        }

        function Copy-DbaDatabaseMailProfile {

            $sourceProfiles = $sourceServer.Mail.Profiles
            $destProfiles = $destServer.Mail.Profiles

            Write-Message -Message "Migrating mail profiles." -Level Verbose
            foreach ($profile in $sourceProfiles) {

                $profileName = $profile.name
                $copyMailProfileStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $profileName
                    Type              = "Mail Profile"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($profiles.count -gt 0 -and $profiles -notcontains $profileName) {
                    continue
                }

                if ($destProfiles.name -contains $profileName) {
                    if ($force -eq $false) {
                        $copyMailProfileStatus.Status = "Skipped"
                        $copyMailProfileStatus.Notes = "Already exists"
                        $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Message "Profile $profileName exists at destination. Use -Force to drop and migrate." -Level Verbose
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destination, "Dropping profile $profileName and recreating.")) {
                        try {
                            Write-Message -Message "Dropping profile $profileName." -Level Verbose
                            $destServer.Mail.Profiles[$profileName].Drop()
                            $destServer.Mail.Profiles.Refresh()
                        }
                        catch {
                            $copyMailProfileStatus.Status = "Failed"
                            $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue dropping profile." -Target $profileName -Category InvalidOperation -InnerErrorRecord $_ -Continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destination, "Migrating mail profile $profileName.")) {
                    try {
                        Write-Message -Message "Copying mail profile $profileName." -Level Verbose
                        $sql = $profile.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $destServer.Mail.Profiles.Refresh()
                        $copyMailProfileStatus.Status = "Successful"
                    }
                    catch {
                        $copyMailProfileStatus.Status = "Failed"
                        $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue copying mail profile." -Target $profileName -Category InvalidOperation -InnerErrorRecord $_
                    }
                }
                $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        }

        function Copy-DbaDatabaseMailServer {
            $sourceMailServers = $sourceServer.Mail.Accounts.MailServers
            $destMailServers = $destServer.Mail.Accounts.MailServers

            Write-Message -Message "Migrating mail servers." -Level Verbose
            foreach ($mailServer in $sourceMailServers) {
                $mailServerName = $mailServer.name
                $copyMailServerStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $mailServerName
                    Type              = "Mail Server"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }
                if ($mailServers.count -gt 0 -and $mailServers -notcontains $mailServerName) {
                    continue
                }

                if ($destMailServers.name -contains $mailServerName) {
                    if ($force -eq $false) {
                        $copyMailServerStatus.Status = "Skipped"
                        $copyMailServerStatus.Notes = "Already exists"
                        $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Message "Mail server $mailServerName exists at destination. Use -Force to drop and migrate." -Level Verbose
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destination, "Dropping mail server $mailServerName and recreating.")) {
                        try {
                            Write-Message -Message "Dropping mail server $mailServerName." -Level Verbose
                            $destServer.Mail.Accounts.MailServers[$mailServerName].Drop()
                        }
                        catch {
                            $copyMailServerStatus.Status = "Failed"
                            $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue dropping mail server." -Target $mailServerName -Category InvalidOperation -InnerErrorRecord $_ -Continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destination, "Migrating account mail server $mailServerName.")) {
                    try {
                        Write-Message -Message "Copying mail server $mailServerName." -Level Verbose
                        $sql = $mailServer.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $copyMailServerStatus.Status = "Successful"
                    }
                    catch {
                        $copyMailServerStatus.Status = "Failed"
                        $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue copying mail server" -Target $mailServerName -Category InvalidOperation -InnerErrorRecord $_
                    }
                }
                $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        }

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName


        if ($sourceServer.versionMajor -lt 9 -or $destServer.versionMajor -lt 9) {
            Write-Message -Message "Database Mail is only supported in SQL Server 2005 and above. Quitting." -Level Verbose
        }

        $mail = $sourceServer.mail
    }
    process {

        if ($type.count -gt 0) {

            switch ($type) {
                "ConfigurationValues" {
                    Copy-DbaDatabaseMailConfig
                    $destServer.Mail.ConfigurationValues.Refresh()
                }

                "Profiles" {
                    Copy-DbaDatabaseMailProfile
                    $destServer.Mail.Profiles.Refresh()
                }

                "Accounts" {
                    Copy-DbaDatabaseAccount
                    $destServer.Mail.Accounts.Refresh()
                }

                "mailServers" {
                    Copy-DbaDatabaseMailServer
                }
            }

            return
        }

        if (($profiles.count + $accounts.count + $mailServers.count) -gt 0) {

            if ($profiles.count -gt 0) {
                Copy-DbaDatabaseMailProfile -Profiles $profiles
                $destServer.Mail.Profiles.Refresh()
            }

            if ($accounts.count -gt 0) {
                Copy-DbaDatabaseAccount -Accounts $accounts
                $destServer.Mail.Accounts.Refresh()
            }

            if ($mailServers.count -gt 0) {
                Copy-DbaDatabaseMailServer -mailServers $mailServers
            }

            return
        }

        Copy-DbaDatabaseMailConfig
        $destServer.Mail.ConfigurationValues.Refresh()
        Copy-DbaDatabaseAccount
        $destServer.Mail.Accounts.Refresh()
        Copy-DbaDatabaseMailProfile
        $destServer.Mail.Profiles.Refresh()
        Copy-DbaDatabaseMailServer
        $copyMailConfigStatus
        $copyMailAccountStatus
        $copyMailProfileStatus
        $copyMailServerStatus
        $enableDBMailStatus

        <# ToDo: Use Get/Set-DbaSpConfigure once the dynamic parameters are replaced. #>

        $sourceDbMailEnabled = ($sourceServer.Configuration.DatabaseMailEnabled).ConfigValue
        Write-Message -Message "$sourceServer DBMail configuration value: $sourceDbMailEnabled." -Level Verbose

        $destDbMailEnabled = ($destServer.Configuration.DatabaseMailEnabled).ConfigValue
        Write-Message -Message "$destServer DBMail configuration value: $destDbMailEnabled." -Level Verbose
        $enableDBMailStatus = [pscustomobject]@{
            SourceServer      = $sourceServer.name
            DestinationServer = $destServer.name
            Name              = "Enabled on Destination"
            Type              = "Mail Configuration"
            Status            = if ($destDbMailEnabled -eq 1) { "Enabled" } else { $null }
            DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
        }

        if (($sourceDbMailEnabled -eq 1) -and ($destDbMailEnabled -eq 0)) {
            if ($pscmdlet.ShouldProcess($destination, "Enabling Database Mail")) {
                try {
                    Write-Message -Message "Enabling Database Mail on $destServer." -Level Verbose
                    $destServer.Configuration.DatabaseMailEnabled.ConfigValue = 1
                    $destServer.Alter()
                    $enableDBMailStatus.Status = "Successful"
                }
                catch {
                    $enableDBMailStatus.Status = "Failed"
                    $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Stop-Function -Message "Cannot enable Database Mail." -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
                }
            }
            $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlDatabaseMail
    }
}
