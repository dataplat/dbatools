Function Get-DbaDiagnosticInfo
{
<#
.SYNOPSIS
Collects information about environment where DBAtools is being executed from.

.DESCRIPTION
Collects information about environment where DBAtools is being executed from. The information will be helpful for troubleshooting issues reported by users.
    

.PARAMETER Detailed
Capture detailed information.

.NOTES 
Original Author: Chrissy LeMaire

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaDiagnosticInfo

.EXAMPLE
Get-DbaDiagnosticInfo

This will collect basic information about the computer where DBAtools is being executed from. It will then show the information in the conslole and at the same time COPY it. After running the cmdlet just paste it where ever you are reporting the issue: GitHub issues, email, or SQLcommunity slack channel etc.

.EXAMPLE   
Get-DbatoolsEnvironmentInfo -Detailed

This will show MORE DETAILED information about the computer where DBAtools is being executed from.
    
#>
    Param (
        #[string]$ComputerName = "$ENV:COMPUTERNAME",
        [switch]$Detailed,
        [switch]$Clip
    )
    
    try
    {
        
        # #Write-Verbose "Collecting information about the computer where DBAtools is excuted from"

        Write-Verbose "Getting local enivornment information"
        $localinfo = @{ } | Select-Object OSVersion, OsArchitecture,PowerShellVersion, PowerShellArchitecture, DbaToolsVersion, ModuleBase, CLR, SMO, DomainUser, RunAsAdmin, isPowerShellISE
        
        $localinfo.OSversion = [environment]::OSVersion.Version.ToString() 
        $OsVersion = (Get-CimInstance CIM_OperatingSystem).Caption.ToString()
        $localinfo.OSversion = $OsVersion + "(" + $localinfo.OSversion + ")"
        
        $localinfo.OsArchitecture = (Get-CimInstance CIM_OperatingSystem).OSArchitecture.ToString()

        $localinfo.PowerShellVersion = $PSVersionTable.PSversion.ToString()

        #If([Environment]::Is64BitProcess -eq $True) #Works on Powershell 3.0/.Net 4 and above
        #$env:PROCESSOR_ARCHITECTURE -eq 'AMD64' 
        If([Intptr]::Size -eq 8) {
            $localinfo.PowerShellArchitecture = "64-bit PowerShell"
        }
        else{
            $localinfo.PowerShellArchitecture = "32-bit PowerShell"
        }

        $localinfo.DbaToolsVersion = (Get-Module dbatools).Version.ToString()
        $localinfo.ModuleBase = (Get-Module dbatools).ModuleBase.ToString() -replace "\\users\\\w+\\","\users\...\"
        $localinfo.CLR = $PSVersionTable.CLRVersion.ToString()
     
        $smo = (([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }).FullName -Split ", ")[1]
        $localinfo.SMO = $smo.TrimStart("Version=")
        
        $localinfo.DomainUser = $env:computername -ne $env:USERDOMAIN
        $localinfo.RunAsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        $localinfo.isPowerShellISE = [Environment]::CommandLine -match 'ise.exe'  
                
        #$localinfo
    }
    
    catch
    {
        Write-Warning "Can't collect info"
        $_.Exception.Message
        return
        # break
    }

    if ($Detailed -eq $true)
        {
            if($Clip -eq $true)
            {
            Write-Output ""   
            Write-Output "Detailed information about the workstation is collected and copied to the clipboard; you can paste it elsewhere."
            Write-Output "" 

            $localinfo | clip  

            }
            else {
            return $localinfo
            }  
            
            
            #may be add all environment variables back using Get-ChildItem Env: ?
            #Also Fred recommended a function to collect diagnostic data from memory and log (but can also be implemented here as a switch)
        }
    else {
            
            $BasicLocalInfo = $localinfo | Select-Object OSVersion, OsArchitecture,PowerShellVersion, PowerShellArchitecture, DbaToolsVersion, ModuleBase, CLR, SMO, DomainUser, RunAsAdmin, isPowerShellISE
            
            if($Clip -eq $true)
            {
            Write-Output "" 
            Write-Output "Basic information about the workstation is collected and copied to the clipboard; you can paste it elsewhere."
            Write-Output "" 
            $BasicLocalInfo | clip
            }
            else {
            return $BasicLocalInfo
            }
            
    }

}
