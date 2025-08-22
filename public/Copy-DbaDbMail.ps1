function Copy-DbaDbMail {
    <#
    .SYNOPSIS
        Copies Database Mail configuration including profiles, accounts, mail servers and settings between SQL Server instances.

    .DESCRIPTION
        Migrates the complete Database Mail setup from a source SQL Server to one or more destination servers. This includes mail profiles (which group accounts for specific purposes), mail accounts (SMTP configurations), mail servers (SMTP server details and credentials), and global configuration values like account retry attempts and maximum file size.

        Database Mail is commonly used for automated alerts, backup notifications, job failure reports, and maintenance notifications. This function saves significant manual configuration time when setting up new servers, standardizing mail configurations across environments, or migrating to new hardware.

        The function preserves all SMTP authentication details including encrypted passwords, handles name conflicts with optional force replacement, and can enable Database Mail on the destination if it's enabled on the source. You can migrate specific component types or the entire configuration in one operation.

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

    .PARAMETER Type
        Specifies the object type to migrate. Valid options are 'ConfigurationValues', 'Profiles', 'Accounts', and 'MailServers'. When Type is specified, all categories from the selected type will be migrated.

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

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaDbMail

    .EXAMPLE
        PS C:\> Copy-DbaDbMail -Source sqlserver2014a -Destination sqlcluster

        Copies all database mail objects from sqlserver2014a to sqlcluster using Windows credentials. If database mail objects with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaDbMail -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all database mail objects from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaDbMail -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    .EXAMPLE
        PS C:\> Copy-DbaDbMail -Source sqlserver2014a -Destination sqlcluster -EnableException

        Performs execution of function, and will throw a terminating exception if something breaks

    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [Parameter(ParameterSetName = 'SpecificTypes')]
        [ValidateSet('ConfigurationValues', 'Profiles', 'Accounts', 'MailServers')]
        [string[]]$Type,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
        function Copy-DbaDbMailConfig {
            [cmdletbinding(SupportsShouldProcess)]
            param ()

            Write-Message -Message "Migrating mail server configuration values." -Level Verbose
            $copyMailConfigStatus = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = "Server Configuration"
                Type              = "Mail Configuration"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }
            if ($pscmdlet.ShouldProcess($destinstance, "Migrating all mail server configuration values.")) {
                try {
                    $sql = $mail.ConfigurationValues.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                    Write-Message -Message $sql -Level Debug
                    $destServer.Query($sql) | Out-Null
                    $mail.ConfigurationValues.Refresh()
                    $copyMailConfigStatus.Status = "Successful"
                    $copyMailConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $copyMailConfigStatus.Status = "Failed"
                    $copyMailConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Unable to update mail server configuration on $destinstance | $PSItem"
                    continue
                }
            }
        }

        function Copy-DbaDatabaseAccount {
            [cmdletbinding(SupportsShouldProcess)]
            $sourceAccounts = $sourceServer.Mail.Accounts
            $destAccounts = $destServer.Mail.Accounts

            Write-Message -Message "Migrating accounts." -Level Verbose
            foreach ($account in $sourceAccounts) {
                $accountName = $account.name
                $newAccountName = $accountName -replace [Regex]::Escape($source), $destinstance
                Write-Message -Message "Updating account name from '$accountName' to '$newAccountName'." -Level Verbose
                $copyMailAccountStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $accountName
                    Type              = "Mail Account"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($accounts.count -gt 0 -and $accounts -notcontains $newAccountName) {
                    continue
                }

                if ($destAccounts.name -contains $newAccountName) {
                    if ($force -eq $false) {
                        If ($pscmdlet.ShouldProcess($destinstance, "Account '$newAccountName' exists at destination. Use -Force to drop and migrate.")) {
                            $copyMailAccountStatus.Status = "Skipped"
                            $copyMailAccountStatus.Notes = "Already exists on destination"
                            $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Message "Account $newAccountName exists at destination. Use -Force to drop and migrate." -Level Verbose
                        }
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destinstance, "Dropping account '$newAccountName' and recreating.")) {
                        try {
                            Write-Message -Message "Dropping account '$newAccountName'." -Level Verbose
                            $destServer.Mail.Accounts[$newAccountName].Drop()
                            $destServer.Mail.Accounts.Refresh()
                        } catch {
                            $copyMailAccountStatus.Status = "Failed"
                            $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue dropping and recreating mail account $newAccountName on $destinstance | $PSItem"
                            continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destinstance, "Migrating account '$accountName'.")) {
                    try {
                        Write-Message -Message "Copying mail account '$accountName'." -Level Verbose
                        $sql = $account.Script() | Out-String
                        $sql = $sql -replace "(?<=@account_name=N'[\d\w\s']*)$sourceRegEx(?=[\d\w\s']*',)", $destinstance
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $copyMailAccountStatus.Status = "Successful"
                    } catch {
                        $copyMailAccountStatus.Status = "Failed"
                        $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue copying mail account $accountName to $destinstance | $PSItem"
                        continue
                    }
                    $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }

        function Copy-DbaDbMailProfile {

            $sourceProfiles = $sourceServer.Mail.Profiles
            $destProfiles = $destServer.Mail.Profiles

            Write-Message -Message "Migrating mail profiles." -Level Verbose
            foreach ($profile in $sourceProfiles) {

                $profileName = $profile.name
                $newProfileName = $profileName -replace [Regex]::Escape($source), $destinstance
                Write-Message -Message "Updating profile name from '$profileName' to '$newProfileName'." -Level Verbose
                $copyMailProfileStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $profileName
                    Type              = "Mail Profile"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($profiles.count -gt 0 -and $profiles -notcontains $newProfileName) {
                    continue
                }

                if ($destProfiles.name -contains $newProfileName) {
                    if ($force -eq $false) {
                        If ($pscmdlet.ShouldProcess($destinstance, "Profile '$newProfileName' exists at destination. Use -Force to drop and migrate.")) {
                            $copyMailProfileStatus.Status = "Skipped"
                            $copyMailProfileStatus.Notes = "Already exists on destination"
                            $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Message "Profile '$newProfileName' exists at destination. Use -Force to drop and migrate." -Level Verbose
                        }
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destinstance, "Dropping profile '$newProfileName' and recreating.")) {
                        try {
                            Write-Message -Message "Dropping profile '$newProfileName'." -Level Verbose
                            $destServer.Mail.Profiles[$newProfileName].Drop()
                            $destServer.Mail.Profiles.Refresh()
                        } catch {
                            $copyMailProfileStatus.Status = "Failed"
                            $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue dropping mail profile $newProfileName on $destinstance | $PSItem"
                            continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destinstance, "Migrating mail profile '$profileName'.")) {
                    try {
                        Write-Message -Message "Copying mail profile '$profileName'." -Level Verbose
                        $sql = $profile.Script() | Out-String
                        $sql = $sql -replace "(?<=@account_name=N'[\d\w\s']*)$sourceRegEx(?=[\d\w\s']*',)", $destinstance
                        $sql = $sql -replace "(?<=@profile_name=N'[\d\w\s']*)$sourceRegEx(?=[\d\w\s']*',)", $destinstance
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $destServer.Mail.Profiles.Refresh()
                        $copyMailProfileStatus.Status = "Successful"
                        $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyMailProfileStatus.Status = "Failed"
                        $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue copying mail profile $profileName to $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }

        function Copy-DbaDbMailServer {
            [cmdletbinding(SupportsShouldProcess)]
            $sourceMailServers = $sourceServer.Mail.Accounts.MailServers
            $destMailServers = $destServer.Mail.Accounts.MailServers

            Write-Message -Message "Getting mail server credentials." -Level Verbose
            $sql = "SELECT credentials.name AS credential_name, sysmail_server.account_id FROM sys.credentials JOIN msdb.dbo.sysmail_server ON credentials.credential_id = sysmail_server.credential_id"
            $credentialAccounts = @($sourceServer.Query($sql))
            if ($credentialAccounts.Count -gt 0) {
                $decryptedCredentials = Get-DecryptedObject -SqlInstance $sourceServer -Type Credential | Where-Object { $_.Name -in $credentialAccounts.credential_name }
            }

            Write-Message -Message "Migrating mail servers." -Level Verbose
            foreach ($mailServer in $sourceMailServers) {
                $mailServerName = $mailServer.name
                $copyMailServerStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $mailServerName
                    Type              = "Mail Server"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }
                if ($mailServers.count -gt 0 -and $mailServers -notcontains $mailServerName) {
                    continue
                }

                if ($destMailServers.name -contains $mailServerName) {
                    if ($force -eq $false) {
                        if ($pscmdlet.ShouldProcess($destinstance, "Mail server $mailServerName exists at destination. Use -Force to drop and migrate.")) {
                            $copyMailServerStatus.Status = "Skipped"
                            $copyMailServerStatus.Notes = "Already exists on destination"
                            $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Message "Mail server $mailServerName exists at destination. Use -Force to drop and migrate." -Level Verbose
                        }
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destinstance, "Dropping mail server $mailServerName and recreating.")) {
                        try {
                            Write-Message -Message "Dropping mail server $mailServerName." -Level Verbose
                            $destServer.Mail.Accounts.MailServers[$mailServerName].Drop()
                        } catch {
                            $copyMailServerStatus.Status = "Failed"
                            $copyMailServerStatus.Notes = (Get-ErrorMessage -Record $_)
                            $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Failed to drop and recreate mail server $mailServerName on $destinstance | $PSItem"
                            continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destinstance, "Migrating account mail server $mailServerName.")) {
                    try {
                        Write-Message -Message "Copying mail server $mailServerName." -Level Verbose
                        $sql = $mailServer.Script() | Out-String
                        $sql = $sql -replace "(?<=@account_name=N'[\d\w\s']*)$sourceRegEx(?=[\d\w\s']*',)", $destinstance
                        $credentialName = ($credentialAccounts | Where-Object { $_.account_id -eq $mailServer.Parent.ID }).credential_name
                        if ($credentialName) {
                            $decryptedCred = $decryptedCredentials | Where-Object { $_.Name -eq $credentialName }
                            if ($decryptedCred) {
                                $password = $decryptedCred.Password.Replace("'", "''")
                                $sql = $sql -replace "@password=N''", "@password=N'$($password)'"
                            } else {
                                Write-Message -Level Warning -Message "Failed to get mail server password, it will need to be entered manually on the destination."
                            }
                        }
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $copyMailServerStatus.Status = "Successful"
                        $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyMailServerStatus.Status = "Failed"
                        $copyMailServerStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue copying mail server $mailServerName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }

        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $mail = $sourceServer.mail
        $sourceRegEx = [RegEx]::Escape($source)
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            if ($type.Count -gt 0) {

                switch ($type) {
                    "ConfigurationValues" {
                        Copy-DbaDbMailConfig
                        $destServer.Mail.ConfigurationValues.Refresh()
                    }

                    "Profiles" {
                        Copy-DbaDbMailProfile
                        $destServer.Mail.Profiles.Refresh()
                    }

                    "Accounts" {
                        Copy-DbaDatabaseAccount
                        $destServer.Mail.Accounts.Refresh()
                    }

                    "mailServers" {
                        Copy-DbaDbMailServer
                    }
                }

                continue
            }

            if (($profiles.count + $accounts.count + $mailServers.count) -gt 0) {

                if ($profiles.count -gt 0) {
                    Copy-DbaDbMailProfile -Profiles $profiles
                    $destServer.Mail.Profiles.Refresh()
                }

                if ($accounts.count -gt 0) {
                    Copy-DbaDatabaseAccount -Accounts $accounts
                    $destServer.Mail.Accounts.Refresh()
                }

                if ($mailServers.count -gt 0) {
                    Copy-DbaDbMailServer -mailServers $mailServers
                }

                continue
            }

            Copy-DbaDbMailConfig
            $destServer.Mail.ConfigurationValues.Refresh()
            Copy-DbaDatabaseAccount
            $destServer.Mail.Accounts.Refresh()
            Copy-DbaDbMailProfile
            $destServer.Mail.Profiles.Refresh()
            Copy-DbaDbMailServer
            $copyMailConfigStatus
            $copyMailAccountStatus
            $copyMailProfileStatus
            $copyMailServerStatus
            $enableDBMailStatus

            <# ToDo: Use Get/Set-DbaSpConfigure once the dynamic parameters are replaced. #>

            if (($sourceDbMailEnabled -eq 1) -and ($destDbMailEnabled -eq 0)) {
                if ($pscmdlet.ShouldProcess($destinstance, "Enabling Database Mail")) {
                    $sourceDbMailEnabled = ($sourceServer.Configuration.DatabaseMailEnabled).ConfigValue
                    Write-Message -Message "$sourceServer DBMail configuration value: $sourceDbMailEnabled." -Level Verbose

                    $destDbMailEnabled = ($destServer.Configuration.DatabaseMailEnabled).ConfigValue
                    Write-Message -Message "$destServer DBMail configuration value: $destDbMailEnabled." -Level Verbose
                    $enableDBMailStatus = [PSCustomObject]@{
                        SourceServer      = $sourceServer.name
                        DestinationServer = $destServer.name
                        Name              = "Enabled on Destination"
                        Type              = "Mail Configuration"
                        Status            = if ($destDbMailEnabled -eq 1) { "Enabled" } else { $null }
                        DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                    }
                    try {
                        Write-Message -Message "Enabling Database Mail on $destServer." -Level Verbose
                        $destServer.Configuration.DatabaseMailEnabled.ConfigValue = 1
                        $destServer.Alter()
                        $enableDBMailStatus.Status = "Successful"
                        $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $enableDBMailStatus.Status = "Failed"
                        $enableDBMailStatus.Notes = (Get-ErrorMessage -Record $_)
                        $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Cannot enable database mail on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}