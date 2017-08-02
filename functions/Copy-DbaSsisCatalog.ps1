function Copy-DbaSsisCatalog {
    <#
.SYNOPSIS 
Copy-DbaSsisCatalog migrates Folders, SSIS projects, and environments from one SQL Server to another. 

.DESCRIPTION
By default, all folders, projects, and environments are copied. 
The -Project parameter can be specified to copy only one project, if desired.
The parameters get more granular from the Folder level.  i.e. specifying folder will only deploy projects/environments from within that folder.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2012 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2012 or greater.

.PARAMETER Force
Drops and recreates the SSIS Catalog if it exists

.PARAMETER Project
Specify a source Project name.

.PARAMETER Folder
Specify a source folder name.

.PARAMETER Environment
Specify an environment to copy over.

.PARAMETER EnableSqlClr
If the destination does not have SQL CLR configuration option enabled (which is required for SSISDB), providing this parameter will skip user prompts for enabling CLR on the destination.

.PARAMETER CreateCatalogPassword
If a destination SSISDB catalog needs to be created, specify this secure string parameter to skip password prompts.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.NOTES
Tags: Migration, SSIS
Original Author: Phil Schwartz (philschwartz.me, @pschwartzzz)
	
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-DbaSsisCatalog
	
.EXAMPLE   
Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster

Copies all folders, environments and all ssis Projects from sqlserver2014a to sqlcluster, using Windows credentials. If folders with the same name exist on the destination they will be skipped, but projects will be redeployed.

.EXAMPLE   
Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -Project Archive_Tables -SourceSqlCredential $cred -Force

Copies a single Project, the Archive_Tables Project from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster. If a Project with the same name exists on sqlcluster, it will be deleted and recreated because -Force was used.

.EXAMPLE   
Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.

.EXAMPLE
$SecurePW = Read-Host "Enter password" -AsSecureString
Copy-DbaSsisCatalog -Source sqlserver2014a -Destination sqlcluster -CreateCatalogPassword $SecurePW

Deploy entire SSIS catalog to an instance without a destination catalog.  Passing -CreateCatalogPassword will bypass any user prompts for creating the destination catalog.

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
            $result = Get-Service -ComputerName $Computer -Name msdts*
            if ($result.Count -gt 0) {
                $running = $false
                foreach ($service in $result) {
                    if (!$service.Status -eq "Running") {
                        Write-Warning "Service $($service.DisplayName) was found on the destination, but is currently not running."
                    }
                    else {
                        Write-Verbose "Service $($service.DisplayName) was found running on the destination."
                        $running = $true
                    }
                }
                if (!$running) {
                    throw "No Integration Services' service was found running on the destination."
                }
            }
            else {
                throw "No Integration Services' service was found on the destination, please ensure the feature is installed and running."
            }
        }
		
        Function Invoke-ProjectDeployment {
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
                if ($results -ne $null) {
                    $destFolder = $destinationFolders | Where-Object { $_.Name -eq $Folder }
                    $deployedProject = $destFolder.DeployProject($Project, $results)
                    if ($deployedProject.Status -ne "Success") {
                        Write-Error "An error occured deploying project $Project."
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
            throw "An error occured when checking the destination for Integration Services. Is Integration Services installed?"
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
                            0 { continue }
                            1 { return }
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
                        0 { New-SSISDBCatalog }
                        1 { return }
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
            try { $destinationFolders.Alter() }
            catch { } # Sometimes it says Alter() doesn't exist
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
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlSsisCatalog
    }
}
