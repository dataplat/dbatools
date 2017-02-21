Function Unregister-DbaWatchUpdate
{
<# 
.SYNOPSIS 
Removes the scheduled task created by Watch-DbaUpdate so that notifications no longer pop up.

.DESCRIPTION 
Removes the scheduled task created by Watch-DbaUpdate so that notifications no longer pop up.

.NOTES
Tags: JustForFun
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Unregister-DbaWatchUpdate

.EXAMPLE   
Unregister-DbaWatchUpdate

Removes the scheduled task created by Watch-DbaUpdate.
#>	
	process
	{
		if (([Environment]::OSVersion).Version.Major -lt 10)
		{
			Write-Warning "This command only supports Windows 10 and above"
			return
		}
		
		$script = {
			
			try
			{
				$task = Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue
				if ($null -eq $task)
				{
					Write-Warning "Task doesn't exist - nothing to do."
					return
				}
				
				$task | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
				$file = "$env:LOCALAPPDATA\dbatools\watchupdate.xml"
				Remove-Item $file -ErrorAction SilentlyContinue
			}
			catch
			{
				Write-Warning "Task could not be deleted."	
			}
		}
		
		# Needs admin creds to remove the task because of the way it was setup
		If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
		{
			return (Start-Process powershell -Verb runAs -ArgumentList $script.tostring() -ErrorAction Stop)
		}
		else
		{
			return (Invoke-Command -ScriptBlock $script -ErrorAction Stop)
		}
	}
}