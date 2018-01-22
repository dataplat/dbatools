function Copy-DbaSsisCatalog {
    <#
        .SYNOPSIS
           Copy-DbaSsisCatalog migrates Folders, SSIS projects, and environments from one SQL Server to another.

        .DESCRIPTION
            By default, all folders, projects, and environments are copied. The -Project parameter can be specified to copy only one project, if desired.

            The parameters get more granular from the Folder level. For example, specifying -Folder will only deploy projects/environments from within that folder.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2012 or higher.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2012 or higher.

        .PARAMETER DestinationSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Force
            If this switch is enabled, the SSIS Catalog will be dropped and recreated on Destination if it already exists.

        .PARAMETER Project
            Specifies a source Project name.

        .PARAMETER Folder
            Specifies a source folder name.

        .PARAMETER Environment
            Specifies an environment to copy.

        .PARAMETER EnableSqlClr
            If this switch is enabled and Destination does not have the SQL CLR configuration option enabled, user prompts for enabling it on Destination will be skipped. SQL CLR is required for SSISDB.

        .PARAMETER CreateCatalogPassword
            Specifies a secure string to use in creating an SSISDB catalog on Destination. If this is specified, prompts for the password will be skipped.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            Tags: Migration, SSIS
            Author: Phil Schwartz (philschwartz.me, @pschwartzzz)

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-DbaSsisCatalog

        .EXAMPLE
            Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster

            Copies all folders, environments and SSIS Projects from sqlserver2014a to sqlcluster, using Windows credentials to authenticate to both instances. If folders with the same name exist on the destination they will be skipped, but projects will be redeployed.

        .EXAMPLE
            Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -Project Archive_Tables -SourceSqlCredential $cred -Force

            Copies a single Project, the Archive_Tables Project, from sqlserver2014a to sqlcluster using SQL credentials to authenticate to sqlserver2014a and Windows credentials to authenticate to sqlcluster. If a Project with the same name exists on sqlcluster, it will be deleted and recreated because -Force was used.

        .EXAMPLE
            Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

            Shows what would happen if the command were executed using force.

        .EXAMPLE
            $SecurePW = Read-Host "Enter password" -AsSecureString
            Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -CreateCatalogPassword $SecurePW

            Deploy entire SSIS catalog to an instance without a destination catalog. User prompts for creating the catalog on Destination will be bypassed.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [String]$Project,
        [String]$Folder,
        [String]$Environment,
        [System.Security.SecureString]$CreateCatalogPassword,
        [Switch]$EnableSqlClr,
        [Switch]$Force
    )

    begin {
        function Get-RemoteIntegrationService {
            param (
                [Object]$Computer
            )
            $result = Get-DbaSqlService -ComputerName $Computer -Type SSIS
            if ($result) {
                $running = $false
                foreach ($service in $result) {
                    if (!$service.State -eq "Running") {
                        Write-Warning "Service $($service.DisplayName) was found on the destination, but is currently not running."
                    }
                    else {
                        Write-Verbose "Service $($service.DisplayName) was found running on the destination."
                        $running = $true
                    }
                }
                if (!$running) {
                    throw "No Integration Services service was found running on the destination."
                }
            }
            else {
                throw "No Integration Services service was found on the destination, please ensure the feature is installed and running."
            }
        }

        function Invoke-ProjectDeployment {
            param (
                [String]$Project,
                [String]$Folder
            )
            $sqlConn = New-Object System.Data.SqlClient.SqlConnection
            $sqlConn.ConnectionString = $sourceConnection.ConnectionContext.ConnectionString
            if ($sqlConn.State -eq "Closed") {
                $sqlConn.Open()
            }
            try {
                Write-Output "Deploying project $Project from folder $Folder."
                $cmd = New-Object System.Data.SqlClient.SqlCommand
                $cmd.CommandType = "StoredProcedure"
                $cmd.connection = $sqlConn
                $cmd.CommandText = "SSISDB.Catalog.get_project"
                $cmd.Parameters.Add("@folder_name", $Folder) | out-null;
                $cmd.Parameters.Add("@project_name", $Project) | out-null;
                [byte[]]$results = $cmd.ExecuteScalar();
                if ($null -ne $results) {
                    $destFolder = $destinationFolders | Where-Object { $_.Name -eq $Folder }
                    $deployedProject = $destFolder.DeployProject($Project, $results)
                    if ($deployedProject.Status -ne "Success") {
                        Write-Error "An error occurred deploying project $Project."
                    }
                }
                else {
                    Write-Error "Failed deploying $Project from folder $Folder."
                    continue
                }
            }
            catch {
                Write-Exception $_
            }
            finally {
                if ($sqlConn.State -eq "Open") {
                    $sqlConn.Close()
                }
            }
        }

        function New-CatalogFolder {
            param (
                [String]$Folder,
                [String]$Description,
                [Switch]$Force
            )
            if ($Force) {
                $remove = $destinationFolders | Where-Object { $_.Name -eq $Folder }
                $envs = $remove.Environments.Name
                foreach ($e in $envs) {
                    $remove.Environments[$e].Drop()
                }
                $projs = $remove.Projects.Name
                foreach ($p in $projs) {
                    $remove.Projects[$p].Drop()
                }
                $remove.Drop()
                $destinationCatalog.Alter()
                $destinationCatalog.Refresh()
            }
            Write-Output "Creating folder $Folder."
            $destFolder = New-Object "$ISNamespace.CatalogFolder" ($destinationCatalog, $Folder, $Description)
            $destFolder.Create()
            $destFolder.Alter()
            $destFolder.Refresh()
        }

        function New-FolderEnvironment {
            param (
                [String]$Folder,
                [String]$Environment,
                [Switch]$Force
            )
            $envDestFolder = $destinationFolders | Where-Object { $_.Name -eq $Folder }
            if ($force) {
                $envDestFolder.Environments[$Environment].Drop()
                $envDestFolder.Alter()
                $envDestFolder.Refresh()
            }
            $srcEnv = ($sourceFolders | Where-Object { $_.Name -eq $Folder }).Environments[$Environment]
            $targetEnv = New-Object "$ISNamespace.EnvironmentInfo" ($envDestFolder, $srcEnv.Name, $srcEnv.Description)
            foreach ($var in $srcEnv.Variables) {
                if ($var.Value.ToString() -eq "") {
                    $finalValue = ""
                }
                else {
                    $finalValue = $var.Value
                }
                $targetEnv.Variables.Add($var.Name, $var.Type, $finalValue, $var.Sensitive, $var.Description)
            }
            Write-Output "Creating environment $Environment."
            $targetEnv.Create()
            $targetEnv.Alter()
            $targetEnv.Refresh()
        }

        function New-SSISDBCatalog {
            param (
                [System.Security.SecureString]$Password
            )

            if (!$Password) {
                Write-Output "SSISDB Catalog requires a password."
                $pass1 = Read-Host "Enter a password" -AsSecureString
                $plainTextPass1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                $pass2 = Read-Host "Re-enter password" -AsSecureString
                $plainTextPass2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))
                if ($plainTextPass1 -ne $plainTextPass2) {
                    throw "Validation error, passwords entered do not match."
                }
                $plainTextPass = $plainTextPass1
            }
            else {
                $plainTextPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
            }

            $catalog = New-Object "$ISNamespace.Catalog" ($destinationSSIS, "SSISDB", $plainTextPass)
            $catalog.Create()
            $catalog.Refresh()
        }

        $ISNamespace = "Microsoft.SqlServer.Management.IntegrationServices"

        $sourceConnection = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destinationConnection = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        if ($sourceConnection.versionMajor -lt 11 -or $destinationConnection.versionMajor -lt 11) {
            throw "SSISDB catalog is only available on Sql Server 2012 and above, exiting..."
        }

        try {
            Get-RemoteIntegrationService -Computer $Destination
        }
        catch {
            Write-Exception $_
            throw "An error occurred when checking the destination for Integration Services. Is Integration Services installed?"
        }

        try {
            Write-Verbose "Connecting to $Source integration services."
            $sourceSSIS = New-Object "$ISNamespace.IntegrationServices" $sourceConnection
        }
        catch {
            Write-Exception $_
            throw "There was an error connecting to the source integration services."
        }
        try {
            Write-Verbose "Connecting to $Destination integration services."
            $destinationSSIS = New-Object "$ISNamespace.IntegrationServices" $destinationConnection
        }
        catch {
            Write-Exception $_
            throw "There was an error connecting to the destination integration services."
        }

        $sourceCatalog = $sourceSSIS.Catalogs | Where-Object { $_.Name -eq "SSISDB" }
        $destinationCatalog = $destinationSSIS.Catalogs | Where-Object { $_.Name -eq "SSISDB" }

        $sourceFolders = $sourceCatalog.Folders
        $destinationFolders = $destinationCatalog.Folders
    }
    process {

        if (!$sourceCatalog) {
            throw "The source SSISDB catalog does not exist."
        }
        if (!$destinationCatalog) {
            if (!$destinationConnection.Configuration.IsSqlClrEnabled.ConfigValue) {
                if ($Pscmdlet.ShouldProcess($Destination, "Enabling SQL CLR configuration option.")) {
                    If (!$EnableSqlClr) {
                        $message = "The destination does not have SQL CLR configuration option enabled (required by SSISDB), would you like to enable it?"
                        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Enable SQL CLR on $Destination."
                        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Exit."
                        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                        $result = $host.ui.PromptForChoice($null, $message, $options, 0)
                        switch ($result) {
                            0 {
                                continue
                            }
                            1 {
                                return
                            }
                        }
                    }
                    Write-Verbose "Enabling SQL CLR configuration option at the destination."
                    if ($destinationConnection.Configuration.ShowAdvancedOptions.ConfigValue -eq $false) {
                        $destinationConnection.Configuration.ShowAdvancedOptions.ConfigValue = $true
                        $changeback = $true
                    }

                    $destinationConnection.Configuration.IsSqlClrEnabled.ConfigValue = $true

                    if ($changeback -eq $true) {
                        $destinationConnection.Configuration.ShowAdvancedOptions.ConfigValue = $false
                    }
                    $destinationConnection.Configuration.Alter()
                }
            }
            else {
                Write-Verbose "SQL CLR configuration option is already enabled at the destination."
            }
            if ($Pscmdlet.ShouldProcess($Destination, "Create destination SSISDB Catalog")) {
                if (!$CreateCatalogPassword) {
                    $message = "The destination SSISDB catalog does not exist, would you like to create one?"
                    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Create an SSISDB catalog on $Destination."
                    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Exit."
                    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                    $result = $host.ui.PromptForChoice($null, $message, $options, 0)
                    switch ($result) {
                        0 {
                            New-SSISDBCatalog
                        }
                        1 {
                            return
                        }
                    }
                }
                else {
                    New-SSISDBCatalog -Password $CreateCatalogPassword
                }

                $destinationSSIS.Refresh()
                $destinationCatalog = $destinationSSIS.Catalogs | Where-Object { $_.Name -eq "SSISDB" }
                $destinationFolders = $destinationCatalog.Folders
            }
            else {
                throw "The destination SSISDB catalog does not exist."
            }
        }
        if ($folder) {
            if ($sourceFolders.Name -contains $folder) {
                $srcFolder = $sourceFolders | Where-Object { $_.Name -eq $folder }
                if ($destinationFolders.Name -contains $folder) {
                    if (!$force) {
                        Write-Warning "Integration services catalog folder $folder exists at destination. Use -Force to drop and recreate."
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess($Destination, "Dropping folder $folder and recreating")) {
                            try {
                                New-CatalogFolder -Folder $srcFolder.Name -Description $srcFolder.Description -Force
                            }
                            catch {
                                Write-Exception $_
                            }

                        }
                    }
                }
                else {
                    if ($Pscmdlet.ShouldProcess($Destination, "Creating folder $folder")) {
                        try {
                            New-CatalogFolder -Folder $srcFolder.Name -Description $srcFolder.Description
                        }
                        catch {
                            Write-Exception $_
                        }
                    }
                }
            }
            else {
                throw "The source folder provided does not exist in the source Integration Services catalog."
            }
        }
        else {
            foreach ($srcFolder in $sourceFolders) {
                if ($destinationFolders.Name -notcontains $srcFolder.Name) {
                    if ($Pscmdlet.ShouldProcess($Destination, "Creating folder $($srcFolder.Name)")) {
                        try {
                            New-CatalogFolder -Folder $srcFolder.Name -Description $srcFolder.Description
                        }
                        catch {
                            Write-Exception $_
                        }
                    }
                }
                else {
                    if (!$force) {
                        Write-Warning "Integration services catalog folder $($srcFolder.Name) exists at destination. Use -Force to drop and recreate."
                        continue
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess($Destination, "Dropping folder $($srcFolder.Name) and recreating")) {
                            try {
                                New-CatalogFolder -Folder $srcFolder.Name -Description $srcFolder.Description -Force
                            }
                            catch {
                                Write-Exception $_
                            }
                        }
                    }
                }
            }
        }

        # Refresh folders for project and environment deployment
        if ($Pscmdlet.ShouldProcess($Destination, "Refresh folders for project deployment")) {
            try {
                $destinationFolders.Alter()
            }
            catch {
                # Sometimes it says Alter() doesn't exist
            }
            $destinationFolders.Refresh()
        }

        if ($folder) {
            $sourceFolders = $sourceFolders | Where-Object { $_.Name -eq $folder }
            if (!$sourceFolders) {
                throw "The source folder $folder does not exist in the source Integration Services catalog."
            }
        }
        if ($project) {
            $folderDeploy = $sourceFolders | Where-Object { $_.Projects.Name -eq $project }
            if (!$folderDeploy) {
                throw "The project $project cannot be found in the source Integration Services catalog."
            }
            else {
                foreach ($f in $folderDeploy) {
                    if ($Pscmdlet.ShouldProcess($Destination, "Deploying project $project from folder $($f.Name)")) {
                        try {
                            Invoke-ProjectDeployment -Folder $f.Name -Project $project
                        }
                        catch {
                            Write-Exception $_
                        }
                    }
                }
            }
        }
        else {
            foreach ($curFolder in $sourceFolders) {
                foreach ($proj in $curFolder.Projects) {
                    if ($Pscmdlet.ShouldProcess($Destination, "Deploying project $($proj.Name) from folder $($curFolder.Name)")) {
                        try {
                            Invoke-ProjectDeployment -Project $proj.Name -Folder $curFolder.Name
                        }
                        catch {
                            Write-Exception $_
                        }
                    }
                }
            }
        }

        if ($environment) {
            $folderDeploy = $sourceFolders | Where-Object { $_.Environments.Name -eq $environment }
            if (!$folderDeploy) {
                throw "The environment $environment cannot be found in the source Integration Services catalog."
            }
            else {
                foreach ($f in $folderDeploy) {
                    if ($destinationFolders[$f.Name].Environments.Name -notcontains $environment) {
                        if ($Pscmdlet.ShouldProcess($Destination, "Deploying environment $environment from folder $($f.Name)")) {
                            try {
                                New-FolderEnvironment -Folder $f.Name -Environment $environment
                            }
                            catch {
                                Write-Exception $_
                            }
                        }
                    }
                    else {
                        if (!$force) {
                            Write-Warning "Integration services catalog environment $environment exists in folder $($f.Name) at destination. Use -Force to drop and recreate."
                        }
                        else {
                            If ($Pscmdlet.ShouldProcess($Destination, "Dropping existing environment $environment and deploying environment $environment from folder $($f.Name)")) {
                                try {
                                    New-FolderEnvironment -Folder $f.Name -Environment $environment -Force
                                }
                                catch {
                                    Write-Exception $_
                                }
                            }
                        }
                    }
                }
            }
        }
        else {
            foreach ($curFolder in $sourceFolders) {
                foreach ($env in $curFolder.Environments) {
                    if ($destinationFolders[$curFolder.Name].Environments.Name -notcontains $env.Name) {
                        if ($Pscmdlet.ShouldProcess($Destination, "Deploying environment $($env.Name) from folder $($curFolder.Name)")) {
                            try {
                                New-FolderEnvironment -Environment $env.Name -Folder $curFolder.Name
                            }
                            catch {
                                Write-Exception $_
                            }
                        }
                    }
                    else {
                        if (!$force) {
                            Write-Warning "Integration services catalog environment $($env.Name) exists in folder $($curFolder.Name) at destination. Use -Force to drop and recreate."
                            continue
                        }
                        else {
                            if ($Pscmdlet.ShouldProcess($Destination, "Deploying environment $($env.Name) from folder $($curFolder.Name)")) {
                                try {
                                    New-FolderEnvironment -Environment $env.Name -Folder $curFolder.Name -Force
                                }
                                catch {
                                    Write-Exception $_
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlSsisCatalog
    }
}
