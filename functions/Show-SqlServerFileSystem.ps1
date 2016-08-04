Function Show-SqlServerFileSystem
{
<#
.SYNOPSIS
Shows file system on remote SQL Server and returns the directory name of the directory you select.
	
.DESCRIPTION
Similar to the remote file system popup you see when browsing a remote SQL Server in SQL Server Management Studio, this command allows you to traverse the remote SQL Server's file structure.

Show-SqlServerFileSystem uses SQL Management Objects to browse the directories and what you see is limited to the permissions of the account running the command.
	
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
https://dbatools.io/Show-SqlServerFileSystem

.EXAMPLE
Show-SqlServerFileSystem -SqlServer sqlserver2014a

Shows a GUI and uses Windows Authentication to log into the SQL Server. Returns a string of the path you selected.
	
.EXAMPLE   
Show-SqlServerFileSystem -Source sqlserver2014a -SqlCredential $cred

Shows a GUI and uses SQL credentials to log into the SQL Server. Returns a string of the path you selected.
	
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
		try { Add-Type -AssemblyName PresentationFramework }
		catch { throw "Windows Presentation Framework required but not installed" }
		
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
				$image.Source = $diskicon
				$textblock.Text = "$name`:"
				$childitem.Tag = "$name`:"
				
			}
			else
			{
				$image.Source = $foldericon
				$textblock.Text = $name
				$childitem.Tag = "$tag\$name"
			}
			
			[void]$stackpanel.Children.Add($image)
			[void]$stackpanel.Children.Add($textblock)
			
			$childitem.Header = $stackpanel
			
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
			try { $dirs = $sourceserver.EnumDirectories($nameSpace) }
			catch { return }
			$subdirs = $dirs.Name
			
			foreach ($subdir in $subdirs)
			{
				if (!$subdir.StartsWith("$") -and $subdir -ne 'System Volume Information')
				{
					Add-TreeItem -Name $subdir -Parent $treeviewItem -Tag $nameSpace
				}
			}
		}
		
		Function Convert-b64toimg
		{
			param ($base64)
			
			$bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
			$bitmap.BeginInit()
			$bitmap.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($base64)
			$bitmap.EndInit()
			$bitmap.Freeze()
			return $bitmap
		}
		
		$diskicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAACxEAAAsRAX9kX5EAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAJtSURBVEhLtZJLa1NBGIa78ze4EZeu3bjS36BduVOsVCGmUqo1QlMaTV3E0oVugm0obdUQTZtYEnNvboTczjlN0ubaWE2aWGhuVQQXKbzOBM+BmokinA48nI+XmefjfDNDAE4dZig3zFBumKHcMEO5YYZywwwppVL5QrG4+217OweO30IiySPJCT1ozQsp7GTzoHvoXpZDpC/4Ut2/nc7sRIhYqO3Xuq1GA512C53WSY46bbSaTVQr1S5pLNAz9OyfPopUlMuf9KFAWO9yeit2uwtWiw1Ohwd+XwBBfxjBAIF+f9dkLzZ9QTg/umGzuuGwe+F0uivBQEhPXcwmJtM6HOSA2+VDOBRBaisNno4nwSOR4PqIx5LgyRhzuQK4NIdYPE7ORXsO6hK9FKkYHb0Po3ENGXIHzVabRP9ex13gsHkI7qcdobwTyUgapncWUBdZ/U3Gxx/j9aoJqVQGpd0KCsWvhPpAavXv8Ls5KCfGcMN7EcOay9CpX8D8/gOoS/RSTjQxLK6QlyRgt1xFvlAn1AZSq/yAZzOCW7pruHpwBlc056C+8xxr5o3BTRSKid6fZHM5VKoH2PvcIjQH0mwcwx/gcFN1HcOxs7ikPI+ZsTnyWHygLtFLkQq1ehZTUxpYrRvI58sQhAIhP5Bsbg9+Txzzcy+hddzDkwUVnk3PY1arA3WJXopUmEwWjIzcheqRGsa3ZjK65b+y8GoJy0tvyEWvY9W+CJvXhqczup6DukQvRSqi0QQMhhVMTk5DqXzYm+v/oFA8IJPQkhdqBnWJXopUnCbMUG6YodwwQ7lhhnLDDOWGGcoNM5QXDP0CA9dqCMSSjzkAAAAASUVORK5CYII="
		$foldericon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAACxEAAAsRAX9kX5EAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAU0SURBVEhLtZXpU5NXFIf9q/qto9bRuhc3xqUiUK3KoLYq6ihu1VIU1DpjRZ3BHVR8i6hUkDUJASNL2EJIWLKvBLJAAmHRpwfb6ai10Q/2w29u3pP3/p57zrn3vnOA/13/CkwMlzLuv0rMfYaoM59R+1ki1lwiFtHgGcIDuYT6fiZoPsWI6SSBnmyGeo4yZDxN2KEQHXr54H3Pdx5mNe6/QnzkGtMxNVNjeqK+AkLWQ/iMWdg7sxnz3uZ1vIrJSBnx0O9MhBQmggqxkRJC9hsEzFc+Dol5cpkcFaNXHbyasTMVNzARqWXEeZv+lh+xG/OIRWrgtU5ebxG1yu9meb+JEct57C+2fwLEe04g95mOPxJV8JphCcPUuBOHfg/6qm/pa8klNvyA6fFqZqbqZaxiZqKWQF8uVm3qp0LuMTNZyfREuUx+JuEo8agLe1smHTXpGLXSB3O+lKqMV5N1UtZypqJ/SCwHS2P6J0Iis5BqgTyR3tyVcIj4mAtL807aq1IxqLJwdR6TJhfL/xUCK3kjn/Ekg9rvPg6JevL/hlQJ5KmU4qGEg9IXCwNN22ir3ES3ap9AjjLqvU48/FBgN0SFeAzZDDSk3nnf852HWY25zxKPFEut/4JMRmcX5mM8bKJPm0bLs/V01e/B2X6IsPMyscAtRt2XRZdwdx1kQPsJ5Rp1nRGIZCKQqZhs09FiCTuJhQyYNFtoLl9HZ20mjtb9BK0XJJsrhG3nZJvn4Wr/AUfbEc+I/fFsI//xfAcwq4gjR0pTxPRkhQAeMh66zavpHkYDWoz1m3j5ZDWd1duxN+9muO80IVuejCcImI7h0W/F2boLtyFfrBJAwtZTjAdvMTn+VFZ/j7HADSbGahh2FGGoWYeuLImOynRsL3bg7zksgGP4DPvwdu2W52wp4wH6NJvFKgEkaP2J6LA0dKxMxruM+q9LFnfxmH+hu3oVTY+S0FekyFbdhrdzr1wnWXg6MnC1phBwVuOxqelvSBOrBJCRgWOM+a9JmUqI+AoJea4SlMY6pamdlStoVJbTVr6BQemPq22ngDJwNm/B3rSKgFuPzz0gmXwEEug7TMTzm5TpDkHXZYbtFxm2XsTenkX7s2VoS76m9cla+lUbcbxMlQxmAclYNEsIuzSE3N0CSRWrBBC/6RBB50XC3kICtl/xD+bh78/DIveWvnwJDQ8W0iJ96atNxtYoIN0GrA1JWOoX4Ler8Dq7MKu3iFUCiK/ngKw8Xy7EAnwDZ6UXOXjkGh/QZdL2dDHq+1/RXLoSc80aMV+LTbsKm3opHvU8buoqKdC1YFKliFUCiKdrr6w8B7/lAu7eUzi7j+PoPCIH8XtaHi9CXTyPZmUJpqqVDKq/wapZgUO9mKB2LqmlVSQ9bKG3fqNYJYA4O3bhMZ2QDHJxdGVj0x/E2rafXnW6QBaiKZ7LS2URpucrGFQtF8hyHJqlDGkXcLz0OnuVUno/loldvwO37He3MQebXB3W1n1yMe7BKBNnIeqiL9GVLHwDsaiWYdMsw6pehl1A7bXraK7birlhh1glgLi6T2Br24tZmyqr34BJvZn+xu1y2r+l9fF86m5+gbZ4PsbnazDXJ9OvXv9mNNUl45LSDck3x91bKFYJIF7TJWVQl6mYNGn6fl0WpoYMeupSaK9Yje7RcjmMqbSWZ9gNz9crxvotSq86TTHWpiiGmk2KUZWuOAyXlBG3Snnb8x3A2wp6m3b6rE+wtp+nq2oDL0oX01CaQndjAVZjbdGH5vyXPhj83Ppg8POKOX8Cx4yjZbQFLr4AAAAASUVORK5CYII="
		$dbatoolsicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAO9SURBVEhL3VVdTFNXHO9MzPTF+OzDeBixFdTMINIWsAUK3AIVkFvAIQVFRLYZKR8Wi1IEKV9DYB8PGFAyEx8QScySabYY5+I2JvK18iWISKGk0JGhLzA3+e2c29uHtpcvH/0lv9yennN+v3vO/3fOFb2fCAg4vXWPNOmMRJ745TtTSskqeElviGXJ0XtkWvjJkyGLPoFAVQZoe/NkX/n6Mh/ysu4Qy7WZdJAutxRW6zT6LcNQaE4LiGgREH4cibpCMNqzCIk9hbScEoSSZ0zKOa7fRxG/k5d1h8ukvO4a5ubmMT1jw5E0vZcBZWzqOTS3dcB8tRXZeRX4/v5DZH5uIu0Wrn8NEzaNDjgYoUPd120oMjViX2iql8H6ZFd8DzE7eFl3iOWpuyQydlh44kbJroilSd8RuQ+cqh7wC9Z+JJaxY8KTN0gp+5Yk9DaREzYhb5FOBwZFZ6LlZifKa5ux//AxYTHCvSEp8A9O5n77B6dwqXS119guZ+GrGq9jfn4eM7ZZxB/PdxN2UfOpHq3kRWq/uoE8Yx3u/fQLzhSYUdN0g+tfN126z0oxNj6BJz0Dq0b4E2UawuJzuPhKyZmKYr/AocgMrk37VzWRBLGRdE/psuXqk9wkT/GNUCJLWqS3By/rDh9FxjaSrnahiZ7cq8wCUzKImLIJqC+Ngbk4gmjjIKKKB6Aq7l+OLBmfVF0YnlQZR1p4eSd2y5IiyEr+oyJ0CwIi0gUNKAOPmnG04Q0utf+DHweWkFjjQOyVWajLpsCUPkeUcRgqAzE09Dfz8k64aqI9YcDziUk87bMgOCZL0CQ0ux2J9UtIbXyFwall/PD0NeLKrU6DkhGymj8RXtRDjU7x8k64TKpJQmi6bLOzSEgv8DYhNWMujiK+9jU0VQs4Vm/H2MwSOh4vcP+rii2cQVh+F+IqbRJe3glyReuoSFBUJtpu3eWulv2h3ueE1iOu0g5N9QL3jLk8jerbdrz59y1yGoYQUdSLsII/CLscIsD9UPrLUz4myXhBhWjCPMVdPBBnhMbsIAZzSDDbcOvRIhyLy6i4+Qyq82QFxECR9xjK/K5OXtodNHo+CsW2tagunbxADbK+sXP16Bv/G7lNQ8hpHEX21UGoDb/j8NmfoSzoNvCymwdTPvMotsKGB32LaL1H0mS0oOHOFLpH/0L3iAOF3/YSk4dgTBMh/JTNgdVbtzNl1il12UuSpHE+SRayTb0IL3yCMP2vUJKtUuh/szNNK8Jfxw3BZNpiMoGjiKPJm54Ffw8gEv0PQRYX7wDAUKEAAAAASUVORK5CYII="
		
		$sourceserver = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SourceSqlCredential
	}
	
	PROCESS
	{		
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
        <TextBox Name="textbox" HorizontalAlignment="Left" Height="Auto" Margin="111,504,0,0" TextWrapping="NoWrap" Text="C:\" VerticalAlignment="Top" Width="292"/>
        <Button Name="okbutton" Content="OK" HorizontalAlignment="Left" Margin="241,540,0,0" VerticalAlignment="Top" Width="75"/>
        <Button Name="cancelbutton" Content="Cancel" HorizontalAlignment="Left" Margin="328.766,540,0,0" VerticalAlignment="Top" Width="75"/>
    </Grid>
</Window>
'
		# Turn XAML into PowerShell objects 
		$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
		$window.icon = $dbatoolsicon
		
		$xaml.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name) -Scope Script }
		
		try { $drives = ($sourceserver.EnumAvailableMedia()).Name }
		catch { throw "No access to remote SQL Server files" }
		
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