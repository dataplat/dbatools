
Function Copy-SqlSsisCatalog
{
<#
.SYNOPSIS 
Copy-SqlSsisCatalog migrates Folders, SSIS projects, and environments from one SQL Server to another. 
.DESCRIPTION
By default, all folders, projects, and environments are copied. 
The -Project parameter can be specified to copy only one project, if desired.
The parameters get more granular from the Folder level.  i.e. specifying folder will only deploy projects/environments from within that folder.
This function must use Integrated security.
.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.
.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.
.PARAMETER Project
Specify a source Project name.
.PARAMETER Folder
Specify a source folder name.
.PARAMETER Environment
Specify an environment to copy over.
.NOTES 
Original Author: Phil Schwartz
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
.LINK
https://dbatools.io/Copy-SqlSsisCatalog
.EXAMPLE   
Copy-SqlSsisCatalog -Source sqlserver2014a -Destination sqlcluster
Copies all folders, environments and all ssis Projects from sqlserver2014a to sqlcluster, using Windows credentials. If folders with the same name exist on the destination they will be skipped, but projects will be redeployed.
.EXAMPLE   
Copy-SqlSsisCatalog -Source sqlserver2014a -Destination sqlcluster -Project Archive_Tables -SourceSqlCredential $cred -Force
Copies a single Project, the Archive_Tables Project from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster. If a Project with the same name exists on sqlcluster, it will be deleted and recreated because -Force was used.
.EXAMPLE   
Copy-SqlSsisCatalog -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force
Shows what would happen if the command were executed using force.
#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [object]$Source,
        [parameter(Mandatory = $true)]
        [object]$Destination,
        [String]$Project,
        [String]$Folder,
        [String]$Environment,
        [switch]$Force
    )
    
    BEGIN
    {
        $folder = $psboundparameters.Folder
        $project = $psboundparameters.Project
        $environment = $psboundparameters.Environment

        $ISNamespace = "Microsoft.SqlServer.Management.IntegrationServices"

        $sourceConnString = "Server=$Source;Initial Catalog=master;Integrated Security=SSPI;"
        $destinationConnString = "Server=$Destination;Initial Catalog=master;Integrated Security=SSPI;"
        $sourceConnection = New-Object System.Data.SqlClient.SqlConnection $sourceConnString       
        $destinationConnection = New-Object System.Data.SqlClient.SqlConnection $destinationConnString
        
        try {
            $sourceConnection.Open()
            $destinationConnection.Open()
        }
        catch {
            If (!$sourceConnection.State -eq "Closed") {
                $sourceConnection.Close()
            }
            If (!$destinationConnection.State -eq "Closed") {
                $destinationConnection.Close()
            }
            Write-Exception $_
        }

        if ($sourceConnection.ServerVersion -lt 11 -or $destinationConnection.ServerVersion -lt 11) {
            throw "SSISDB catalog is only available on Sql Server 2012 and above, exiting..."
        }

        try { 
            Write-Verbose "Connecting to $Source integration services."
            $sourceSSIS = New-Object "$ISNamespace.IntegrationServices" $sourceConnection }
        catch { 
            Write-Error $_ 
        }
        try { 
            Write-Verbose "Connecting to $Destination integration services."
            $destinationSSIS = New-Object "$ISNamespace.IntegrationServices" $destinationConnection 
        }
        catch { 
            Write-Error $_ 
        }

        $sourceCatalog = $sourceSSIS.Catalogs | Where-Object { $_.Name -eq "SSISDB" }  
        $destinationCatalog = $destinationSSIS.Catalogs | Where-Object { $_.Name -eq "SSISDB" } 
        
        $sourceFolders = $sourceCatalog.Folders
        $destinationFolders = $destinationCatalog.Folders	

        Function Deploy-Project {
            param(
                [String]$Project,
                [String]$Folder
            )
            if ($sourceConnection.State -eq "Closed") { 
                $sourceConnection.Open() 
            }  
            try {
                Write-Output "Deploying project $Project from folder $Folder."
                $cmd = New-Object System.Data.SqlClient.SqlCommand  
                $cmd.CommandType = "StoredProcedure"  
                $cmd.connection = $sourceConnection  
                $cmd.CommandText = "SSISDB.Catalog.get_project"  
                $cmd.Parameters.Add("@folder_name",$Folder) | out-null;  
                $cmd.Parameters.Add("@project_name",$Project) | out-null;  
                [byte[]]$results = $cmd.ExecuteScalar();  
                if($results -ne $null) {  
                    $destFolder = $destinationFolders | Where-Object { $_.Name -eq $Folder }
                    $deployedProject = $destFolder.DeployProject($Project,$results)
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
        }

        Function Create-Folder {
            param(
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
        
        Function Create-Environment {
            param(
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
                    $finalValue= ""
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
    }
    PROCESS
    {
        if (!$sourceCatalog) {
            Write-Error "The source SSISDB catalog does not exist."
            exit
        }
        if (!$destinationCatalog) {
            # Todo, prompt to create the catalog?
            Write-Error "The destination SSISDB catalog does not exist."
            exit
        }
        if ($folder) {
            if ($sourceFolders.Name -contains $folder) {
                $srcFolder = $sourceFolders | Where-Object { $_.Name -eq $folder }
                if ($destinationFolders.Name -contains $folder) {
                    if (!$force) {
                        Write-Warning "Integration services catalog folder $folder exists at destination. Use -Force to drop and recreate."
                    }
                    else {
                        If ($Pscmdlet.ShouldProcess($Destination, "Dropping folder $folder and recreating")) {
                            try {
                                Create-Folder -Folder $srcFolder.Name -Description $srcFolder.Description -Force
                            }
                            catch {
                                Write-Exception $_
                            }
                        
                        }
                    }
                }
                else {
                    If ($Pscmdlet.ShouldProcess($Destination, "Creating folder $folder")) {
                        try {
                            Create-Folder -Folder $srcFolder.Name -Description $srcFolder.Description
                        }
                        catch {
                            Write-Exception $_
                        }
                    }
                }
            }
            else {
                Write-Error "The source folder provided does not exist in the source Integration Services catalog."
            }
        }
        else {
            foreach ($srcFolder in $sourceFolders) {
                if($destinationFolders.Name -notcontains $srcFolder.Name) {  
                    If ($Pscmdlet.ShouldProcess($Destination, "Creating folder $($srcFolder.Name)")) {
                        try {
                            Create-Folder -Folder $srcFolder.Name -Description $srcFolder.Description
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
                        If ($Pscmdlet.ShouldProcess($Destination, "Dropping folder $($srcFolder.Name) and recreating")) {
                            try {
                                Create-Folder -Folder $srcFolder.Name -Description $srcFolder.Description -Force
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
        If ($Pscmdlet.ShouldProcess($Destination, "Refresh folders for project deployment")) {
            $destinationFolders.Alter()
            $destinationFolders.Refresh()
        }

        if ($folder) {
            $sourceFolders = $sourceFolders | Where-Object { $_.Name -eq $folder }
            if (!$sourceFolders) {
                Write-Error "The source folder $folder does not exist in the source Integration Services catalog."
            }
        }
        if ($project) {
            $folderDeploy = $sourceFolders | Where-Object { $_.Projects.Name -eq $project }
            if(!$folderDeploy) {
                Write-Error "The project $project cannot be found in the source Integration Services catalog."
            }
            else {
                foreach ($f in $folderDeploy) {
                    If ($Pscmdlet.ShouldProcess($Destination, "Deploying project $project from folder $($f.Name)")) {
                        try {
                            Deploy-Project -Folder $f.Name -Project $project
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
                    If ($Pscmdlet.ShouldProcess($Destination, "Deploying project $($proj.Name) from folder $($curFolder.Name)")) {
                        try {
                            Deploy-Project -Project $proj.Name -Folder $curFolder.Name
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
            if(!$folderDeploy) {
                Write-Error "The environment $environment cannot be found in the source Integration Services catalog."
            }
            else {
                foreach ($f in $folderDeploy) {
                    if ($destinationFolders[$f.Name].Environments.Name -notcontains $environment) {
                        If ($Pscmdlet.ShouldProcess($Destination, "Deploying environment $environment from folder $($f.Name)")) {
                            try {
                                Create-Environment -Folder $f.Name -Environment $environment
                            }
                            catch {
                                Write-Exception $_
                            }
                        }
                    }
                    else {
                        if(!$force) {
                            Write-Warning "Integration services catalog environment $environment exists in folder $($f.Name) at destination. Use -Force to drop and recreate."
                        }
                        else {
                            If ($Pscmdlet.ShouldProcess($Destination, "Dropping existing environment $environment and deploying environment $environment from folder $($f.Name)")) {
                                try {
                                    Create-Environment -Folder $f.Name -Environment $environment -Force
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
                    if ($destinationFolders[$f.Name].Environments.Name -notcontains $env.Name) {
                        If ($Pscmdlet.ShouldProcess($Destination, "Deploying environment $($env.Name) from folder $($curFolder.Name)")) {
                            try {
                                Create-Environment -Environment $env.Name -Folder $curFolder.Name
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
                            If ($Pscmdlet.ShouldProcess($Destination, "Deploying environment $($env.Name) from folder $($curFolder.Name)")) {
                                try {
                                    Create-Environment -Environment $env.Name -Folder $curFolder.Name -Force
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
    
    END
    {
        If ($sourceConnection.State -eq "Open") {
            $sourceConnection.Close()
        }
        If ($destinationConnection.State -eq "Open") {
            $destinationConnection.Close()
        }
        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { 
            Write-Output "Integration services migration finished." 
        }
    }
}