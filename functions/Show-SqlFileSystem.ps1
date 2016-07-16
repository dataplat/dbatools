Function Show-SqlFileSystem
{
<#
.SYNOPSIS

.DESCRIPTION

.PARAMETER SqlServer
The SQL Server instance.
	
.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Show-SqlFileSystem

.EXAMPLE
Show-SqlFileSystem -SqlServer sqlserver2014a

Shows a GUI
	
.EXAMPLE   
Show-SqlFileSystem -Source sqlserver2014a -Destination sqlcluster -SqlCredential $cred

Shows a GUI
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential
	)
	
	BEGIN
	{
		Function Add-TreeItem
		{
			Param (
				[string]$name,
				[object]$parent,
				[string]$tag
			)
			
			$childitem = New-Object System.Windows.Controls.TreeViewItem
			
			$textblock = New-Object System.Windows.Controls.TextBlock
			$textblock.Margin = "5,0"
			
			$stackpanel = New-Object System.Windows.Controls.StackPanel
			$stackpanel.Orientation = "Horizontal"
			
			$image = New-Object System.Windows.Controls.Image
			$image.Height = 20
			$image.Width = 20
			$image.Stretch = "Fill"
			
			if ($name.length -eq 1)
			{
				$image.Source = "C:\temp\diskdrive.png"
				$textblock.Text = "$name`:"
				$childitem.Tag = "$name`:"
				
				[void]$stackpanel.Children.Add($image)
				[void]$stackpanel.Children.Add($textblock)
				
				$childitem.Header = $stackpanel
			}
			else
			{
				$image.source = "C:\temp\folder.png"
				$textblock.Text = $name
				$childitem.Tag = "$tag\$name"
				
				[void]$stackpanel.Children.Add($image)
				[void]$stackpanel.Children.Add($textblock)
				
				$childitem.Header = $stackpanel
			}
			
			[void]$childitem.Items.Add("*")
			[void]$parent.Items.Add($childitem)
		}
		
		Function Get-SubDirectory
		{
			Param (
				[string]$nameSpace,
				[object]$treeviewItem
			)
			
			$textbox.Text = $nameSpace
			$dirs = $server.EnumDirectories($nameSpace)
			$subdirs = $dirs.Name
			
			foreach ($subdir in $subdirs)
			{
				if (!$subdir.StartsWith("$") -and $subdir -ne 'System Volume Information')
				{
					Add-TreeItem -Name $subdir -Parent $treeviewItem -Tag $nameSpace
				}
			}
		}
	}
	
	PROCESS
	{
		# Extract icon from PowerShell to use as the NotifyIcon 
		$icon = [System.Drawing.Icon]::ExtractAssociatedIcon("$pshome\powershell.exe")
		
		# Create XAML form in Visual Studio, ensuring the ListView looks chromeless 
		[xml]$xaml = '<Window 
		xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" 
		xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" 
        Title="Locate Folder" Height="620" Width="440" Background="#F0F0F0"
		WindowStartupLocation="CenterScreen">
    <Grid>
        <TreeView Name="treeview" Height="462" Width="391" Background="#FFFFFF" BorderBrush="#FFFFFF" Foreground="#FFFFFF" Margin="11,36,11,79"/>
        <Label x:Name="label" Content="Select the folder:" HorizontalAlignment="Left" Margin="15,4,0,0" VerticalAlignment="Top"/>
        <Label x:Name="path" Content="Selected Path" HorizontalAlignment="Left" Margin="15,502,0,0" VerticalAlignment="Top"/>
        <TextBox Name="textbox" HorizontalAlignment="Left" Height="23" Margin="111,504,0,0" TextWrapping="Wrap" Text="C:\blah" VerticalAlignment="Top" Width="292"/>
        <Button Name="okbutton" Content="OK" HorizontalAlignment="Left" Margin="241,540,0,0" VerticalAlignment="Top" Width="75"/>
        <Button Name="cancelbutton" Content="Cancel" HorizontalAlignment="Left" Margin="328.766,540,0,0" VerticalAlignment="Top" Width="75"/>
    </Grid>
</Window>
'
		# Turn XAML into PowerShell objects 
		$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
		$xaml.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name) -Scope Script }
		
		$drives = ($sourceserver.EnumAvailableMedia()).Name
		foreach ($drive in $drives)
		{
			$drive = $drive.Replace(":", "")
			Add-TreeItem -Name $drive -Parent $treeview -Tag $drive
		}
		
		$window.Add_SourceInitialized({
				[System.Windows.RoutedEventHandler]$Event = {
					if ($_.OriginalSource -is [System.Windows.Controls.TreeViewItem])
					{
						$treeviewItem = $_.OriginalSource
						$treeviewItem.items.clear()
						Get-SubDirectory -NameSpace $treeviewItem.Tag -TreeViewItem $treeviewItem
					}
				}
				$treeview.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, $Event)
				$treeview.AddHandler([System.Windows.Controls.TreeViewItem]::SelectedEvent, $Event)
			})
		
		$okbutton.Add_Click({
				$window.Close()
			})
		
		$cancelbutton.Add_Click({
				$textbox.Text = $null
				$window.Close()
			})
		
		$null = $window.ShowDialog()
	}
	
	END
	{
		
		if ($textbox.Text.length -gt 0)
		{
			return $textbox.Text
		}
	}
}