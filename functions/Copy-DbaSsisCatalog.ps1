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
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2012 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, SSIS
        Author: Phil Schwartz (philschwartz.me, @pschwartzzz)

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaSsisCatalog

    .EXAMPLE
        PS C:\> Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster

        Copies all folders, environments and SSIS Projects from sqlserver2014a to sqlcluster, using Windows credentials to authenticate to both instances. If folders with the same name exist on the destination they will be skipped, but projects will be redeployed.

    .EXAMPLE
        PS C:\> Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -Project Archive_Tables -SourceSqlCredential $cred -Force

        Copies a single Project, the Archive_Tables Project, from sqlserver2014a to sqlcluster using SQL credentials to authenticate to sqlserver2014a and Windows credentials to authenticate to sqlcluster. If a Project with the same name exists on sqlcluster, it will be deleted and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    .EXAMPLE
        PS C:\> $SecurePW = Read-Host "Enter password" -AsSecureString
        PS C:\> Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -CreateCatalogPassword $SecurePW

        Deploy entire SSIS catalog to an instance without a destination catalog. User prompts for creating the catalog on Destination will be bypassed.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [String]$Project,
        [String]$Folder,
        [String]$Environment,
        [System.Security.SecureString]$CreateCatalogPassword,
        [Switch]$EnableSqlClr,
        [Switch]$Force,
        [switch]$EnableException
    )
    <# Developer note: The throw calls must stay in this command #>
    begin {
        $ISNamespace = "Microsoft.SqlServer.Management.IntegrationServices"

        if ($Force) { $ConfirmPreference = 'none' }

        function Get-RemoteIntegrationService {
            param (
                [Object]$Computer
            )
            $result = Get-DbaService -ComputerName $Computer -Type SSIS
            if ($result) {
                #Variable marked as unused by PSScriptAnalyzer
                #$running = $false
                foreach ($service in $result) {
                    if (!$service.State -eq "Running") {
                        Write-Message -Level Warning -Message "Service $($service.DisplayName) was found on the destination, but is currently not running."
                    } else {
                        Write-Message -Level Verbose -Message "Service $($service.DisplayName) was found running on the destination."
                        #$running = $true
                    }
                }
            } else {
                throw "No Integration Services service was found on the destination, please ensure the feature is installed and running."
            }
        }
        function Invoke-ProjectDeployment {
            param (
                [String]$Project,
                [String]$Folder
            )
            $sqlConn = New-Object System.Data.SqlClient.SqlConnection
            $sqlConn.ConnectionString = $sourceServer.ConnectionContext.ConnectionString
            if ($sqlConn.State -eq "Closed") {
                $sqlConn.Open()
            }
            try {
                Write-Message -Level Verbose -Message "Deploying project $Project from folder $Folder."
                $cmd = New-Object System.Data.SqlClient.SqlCommand
                $cmd.CommandType = "StoredProcedure"
                $cmd.connection = $sqlConn
                $cmd.CommandText = "SSISDB.Catalog.get_project"
                $cmd.Parameters.Add("@folder_name", $Folder) | Out-Null;
                $cmd.Parameters.Add("@project_name", $Project) | Out-Null;
                [byte[]]$results = $cmd.ExecuteScalar();
                if ($null -ne $results) {
                    $destFolder = $destinationFolders | Where-Object {
                        $_.Name -eq $Folder
                    }
                    $deployedProject = $destFolder.DeployProject($Project, $results)
                    if ($deployedProject.Status -ne "Success") {
                        Stop-Function -Message "An error occurred deploying project $Project." -Target $Project -Continue
                    }
                } else {
                    Stop-Function -Message "Failed deploying $Project from folder $Folder." -Target $Project -Continue
                }
            } catch {
                Stop-Function -Message "Failed to deploy project." -Target $Project -ErrorRecord $_
            } finally {
                if ($sqlConn.State -eq "Open") {
                    $sqlConn.Close()
                }
            }
        }
        function New-CatalogFolder {
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [String]$Folder,
                [String]$Description,
                [Switch]$Force
            )
            if ($Pscmdlet.ShouldProcess($folder, "Creating new Catalog Folder")) {
                if ($Force) {
                    $remove = $destinationFolders | Where-Object {
                        $_.Name -eq $Folder
                    }
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
                Write-Message -Level Verbose -Message "Creating folder $Folder."
                $destFolder = New-Object "$ISNamespace.CatalogFolder" ($destinationCatalog, $Folder, $Description)
                $destFolder.Create()
                $destFolder.Alter()
                $destFolder.Refresh()
            }
        }
        function New-FolderEnvironment {
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [String]$Folder,
                [String]$Environment,
                [Switch]$Force
            )
            if ($Pscmdlet.ShouldProcess($folder, "Creating new Environment Folder")) {
                $envDestFolder = $destinationFolders | Where-Object {
                    $_.Name -eq $Folder
                }
                if ($force) {
                    $envDestFolder.Environments[$Environment].Drop()
                    $envDestFolder.Alter()
                    $envDestFolder.Refresh()
                }
                $srcEnv = ($sourceFolders | Where-Object {
                        $_.Name -eq $Folder
                    }).Environments[$Environment]
                $targetEnv = New-Object "$ISNamespace.EnvironmentInfo" ($envDestFolder, $srcEnv.Name, $srcEnv.Description)
                foreach ($var in $srcEnv.Variables) {
                    if ($var.Value.ToString() -eq "") {
                        $finalValue = ""
                    } else {
                        $finalValue = $var.Value
                    }
                    $targetEnv.Variables.Add($var.Name, $var.Type, $finalValue, $var.Sensitive, $var.Description)
                }
                Write-Message -Level Verbose -Message "Creating environment $Environment."
                $targetEnv.Create()
                $targetEnv.Alter()
                $targetEnv.Refresh()
            }
        }
        function New-SSISDBCatalog {
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [System.Security.SecureString]$SecurePassword
            )
            if ($Pscmdlet.ShouldProcess("Creating New SSISDB Catalog")) {
                if (!$Password) {
                    Write-Message -Level Verbose -Message "SSISDB Catalog requires a password."
                    $pass1 = Read-Host "Enter a password" -AsSecureString
                    $plainTextPass1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                    $pass2 = Read-Host "Re-enter password" -AsSecureString
                    $plainTextPass2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))
                    if ($plainTextPass1 -ne $plainTextPass2) {
                        throw "Validation error, passwords entered do not match."
                    }
                    $plainTextPass = $plainTextPass1
                } else {
                    $plainTextPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
                }

                $catalog = New-Object "$ISNamespace.Catalog" ($destinationSSIS, "SSISDB", $plainTextPass)
                $catalog.Create()
                $catalog.Refresh()
            }
        }

        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 11
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        try {
            $sourceSSIS = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $sourceServer
        } catch {
            Stop-Function -Message "There was an error connecting to the source integration services." -Target $sourceServer -ErrorRecord $_
            return
        }

        $sourceCatalog = $sourceSSIS.Catalogs | Where-Object {
            $_.Name -eq "SSISDB"
        }
        if (!$sourceCatalog) {
            Stop-Function -Message "The source SSISDB catalog on $Source does not exist."
            return
        }
        $sourceFolders = $sourceCatalog.Folders
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }
        foreach ($destinstance in $Destination) {
            try {
                $destinationConnection = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 1
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            try {
                Get-RemoteIntegrationService -Computer $destinstance.ComputerName
            } catch {
                Stop-Function -Message "An error occurred when checking the destination for Integration Services. Is Integration Services installed?" -Target $destinstance -ErrorRecord $_
            }

            try {
                $destinationSSIS = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $destinationConnection
            } catch {
                Stop-Function -Message "There was an error connecting to the destination integration services." -Target $destinationCon -ErrorRecord $_
            }

            $destinationCatalog = $destinationSSIS.Catalogs | Where-Object {
                $_.Name -eq "SSISDB"
            }
            $destinationFolders = $destinationCatalog.Folders

            if (!$destinationCatalog) {
                if (!$destinationConnection.Configuration.IsSqlClrEnabled.ConfigValue) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Enabling SQL CLR configuration option.")) {
                        if (!$EnableSqlClr) {
                            $message = "The destination does not have SQL CLR configuration option enabled (required by SSISDB), would you like to enable it?"
                            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Enable SQL CLR on $destinstance."
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
                        Write-Message -Level Verbose -Message "Enabling SQL CLR configuration option at the destination."
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
                } else {
                    Write-Message -Level Verbose -Message "SQL CLR configuration option is already enabled at the destination."
                }
                if ($Pscmdlet.ShouldProcess($destinstance, "Create destination SSISDB Catalog")) {
                    if (!$CreateCatalogPassword) {
                        $message = "The destination SSISDB catalog does not exist, would you like to create one?"
                        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Create an SSISDB catalog on $destinstance."
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
                    } else {
                        New-SSISDBCatalog -SecurePassword $CreateCatalogPassword
                    }

                    $destinationSSIS.Refresh()
                    $destinationCatalog = $destinationSSIS.Catalogs | Where-Object {
                        $_.Name -eq "SSISDB"
                    }
                    $destinationFolders = $destinationCatalog.Folders
                } else {
                    throw "The destination SSISDB catalog does not exist."
                }
            }
            if ($folder) {
                if ($sourceFolders.Name -contains $folder) {
                    $srcFolder = $sourceFolders | Where-Object {
                        $_.Name -eq $folder
                    }
                    if ($destinationFolders.Name -contains $folder) {
                        if (!$force) {
                            Write-Message -Level Warning -Message "Integration services catalog folder $folder exists at destination. Use -Force to drop and recreate."
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping folder $folder and recreating")) {
                                try {
                                    New-CatalogFolder -Folder $srcFolder.Name -Description $srcFolder.Description -Force
                                } catch {
                                    Stop-Function -Message "Issue dropping folder" -Target $folder -ErrorRecord $_
                                }

                            }
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Creating folder $folder")) {
                            try {
                                New-CatalogFolder -Folder $srcFolder.Name -Description $srcFolder.Description
                            } catch {
                                Stop-Function -Message "Issue creating folder" -Target $folder -ErrorRecord $_
                            }
                        }
                    }
                } else {
                    throw "The source folder provided does not exist in the source Integration Services catalog."
                }
            } else {
                foreach ($srcFolder in $sourceFolders) {
                    if ($destinationFolders.Name -notcontains $srcFolder.Name) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Creating folder $($srcFolder.Name)")) {
                            try {
                                New-CatalogFolder -Folder $srcFolder.Name -Description $srcFolder.Description
                            } catch {
                                Stop-Function -Message "Issue creating folder" -Target $srcFolder -ErrorRecord $_ -Continue
                            }
                        }
                    } else {
                        if (!$force) {
                            Write-Message -Level Warning -Message "Integration services catalog folder $($srcFolder.Name) exists at destination. Use -Force to drop and recreate."
                            continue
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping folder $($srcFolder.Name) and recreating")) {
                                try {
                                    New-CatalogFolder -Folder $srcFolder.Name -Description $srcFolder.Description -Force
                                } catch {
                                    Stop-Function -Message "Issue dropping folder" -Target $srcFolder -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
            }

            # Refresh folders for project and environment deployment
            if ($Pscmdlet.ShouldProcess($destinstance, "Refresh folders for project deployment")) {
                try {
                    $destinationFolders.Alter()
                } catch {
                    # Sometimes it says Alter() doesn't exist
                    # here to avoid an empty catch
                    $null = 1
                }
                $destinationFolders.Refresh()
            }

            if ($folder) {
                $sourceFolders = $sourceFolders | Where-Object {
                    $_.Name -eq $folder
                }
                if (!$sourceFolders) {
                    throw "The source folder $folder does not exist in the source Integration Services catalog."
                }
            }
            if ($project) {
                $folderDeploy = $sourceFolders | Where-Object {
                    $_.Projects.Name -eq $project
                }
                if (!$folderDeploy) {
                    throw "The project $project cannot be found in the source Integration Services catalog."
                } else {
                    foreach ($f in $folderDeploy) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Deploying project $project from folder $($f.Name)")) {
                            try {
                                Invoke-ProjectDeployment -Folder $f.Name -Project $project
                            } catch {
                                Stop-Function -Message "Issue deploying project" -Target $project -ErrorRecord $_
                            }
                        }
                    }
                }
            } else {
                foreach ($curFolder in $sourceFolders) {
                    foreach ($proj in $curFolder.Projects) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Deploying project $($proj.Name) from folder $($curFolder.Name)")) {
                            try {
                                Invoke-ProjectDeployment -Project $proj.Name -Folder $curFolder.Name
                            } catch {
                                Stop-Function -Message "Issue deploying project" -Target $proj -ErrorRecord $_
                            }
                        }
                    }
                }
            }

            if ($environment) {
                $folderDeploy = $sourceFolders | Where-Object {
                    $_.Environments.Name -eq $environment
                }
                if (!$folderDeploy) {
                    throw "The environment $environment cannot be found in the source Integration Services catalog."
                } else {
                    foreach ($f in $folderDeploy) {
                        if ($destinationFolders[$f.Name].Environments.Name -notcontains $environment) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Deploying environment $environment from folder $($f.Name)")) {
                                try {
                                    New-FolderEnvironment -Folder $f.Name -Environment $environment
                                } catch {
                                    Stop-Function -Message "Issue deploying environment" -Target $environment -ErrorRecord $_
                                }
                            }
                        } else {
                            if (!$force) {
                                Write-Message -Level Warning -Message "Integration services catalog environment $environment exists in folder $($f.Name) at destination. Use -Force to drop and recreate."
                            } else {
                                If ($Pscmdlet.ShouldProcess($destinstance, "Dropping existing environment $environment and deploying environment $environment from folder $($f.Name)")) {
                                    try {
                                        New-FolderEnvironment -Folder $f.Name -Environment $environment -Force
                                    } catch {
                                        Stop-Function -Message "Issue dropping existing environment" -Target $environment -ErrorRecord $_
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                foreach ($curFolder in $sourceFolders) {
                    foreach ($env in $curFolder.Environments) {
                        if ($destinationFolders[$curFolder.Name].Environments.Name -notcontains $env.Name) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Deploying environment $($env.Name) from folder $($curFolder.Name)")) {
                                try {
                                    New-FolderEnvironment -Environment $env.Name -Folder $curFolder.Name
                                } catch {
                                    Stop-Function -Message "Issue deploying environment" -Target $env -ErrorRecord $_
                                }
                            }
                        } else {
                            if (!$force) {
                                Write-Message -Level Warning -Message "Integration services catalog environment $($env.Name) exists in folder $($curFolder.Name) at destination. Use -Force to drop and recreate."
                                continue
                            } else {
                                if ($Pscmdlet.ShouldProcess($destinstance, "Deploying environment $($env.Name) from folder $($curFolder.Name)")) {
                                    try {
                                        New-FolderEnvironment -Environment $env.Name -Folder $curFolder.Name -Force
                                    } catch {
                                        Stop-Function -Message "Issue deploying environment" -Target $env -ErrorRecord $_
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}