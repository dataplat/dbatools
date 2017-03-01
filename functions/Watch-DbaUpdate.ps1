Function Watch-DbaUpdate
{
<# 
.SYNOPSIS 
Just for fun - checks the PowerShell Gallery every 1 hour for updates to dbatools. Notifies once max per release.

.DESCRIPTION 
Just for fun - checks the PowerShell Gallery every 1 hour for updates to dbatools. Notifies once max per release.
	
Anyone know how to make it clickable so that it opens an URL?

.NOTES
Tags: JustForFun
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Watch-DbaUpdate

.EXAMPLE   
Watch-DbaUpdate

Watches the gallery for updates to dbatools.
#>	

	PROCESS
	{
		if (([Environment]::OSVersion).Version.Major -lt 10)
		{
			Write-Warning "This command only supports Windows 10 and above"
			return
		}
		
		if ($null -eq (Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue))
		{
			Install-DbaWatchUpdate
		}
		
		# leave this in for the scheduled task
		$module = Get-Module -Name dbatools
		
		if (!$module)
		{
			Import-Module dbatools
			$module = Get-Module -Name dbatools
		}
		
		$galleryversion = (Find-Module -Name dbatools -Repository PSGallery).Version
		$localversion = $module.Version
		
		if ($galleryversion -le $localversion) { return }
		
		$file = "$env:LOCALAPPDATA\dbatools\watchupdate.xml"
		
		$new = [pscustomobject]@{
			NotifyVersion = $galleryversion
		}
		
		# now that notifications stay until they are checked, we just have to keep
		# track of the last version we notified about
		
		if (Test-Path $file)
		{
			$old = Import-Clixml -Path $file -ErrorAction SilentlyContinue
			
			if ($galleryversion -gt $old.NotifyVersion)
			{
				Export-Clixml -InputObject $new -Path $file
				Show-Notification
			}
		}
		else
		{
			$directory = Split-Path $file
			
			if (!(Test-Path $directory))
			{
				$null = New-Item -ItemType Directory -Path $directory
			}
			
			Export-Clixml -InputObject $new -Path $file
			Show-Notification
		}
	}
}
