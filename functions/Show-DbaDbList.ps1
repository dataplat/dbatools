function Show-DbaDbList {
    <#
    .SYNOPSIS
        Shows a list of databases in a GUI.

    .DESCRIPTION
        Shows a list of databases in a GUI. Returns a string holding the name of the selected database. Hitting cancel returns null.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances..

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Title
        Title of the window being displayed. Default is "Select Database".

    .PARAMETER Header
        Header text displayed above the database listing. Default is "Select the database:".

    .PARAMETER DefaultDb
        Specify a database to have selected when the window appears.

    .PARAMETER EnableException
        By default in most of our commands, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This command, however, gifts you  with "sea of red" exceptions, by default, because it is useful for advanced scripting.

        Using this switch turns our "nice by default" feature on which makes errors into pretty warnings.

    .NOTES
        Tags: Database, FileSystem
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Show-DbaDbList

    .EXAMPLE
        PS C:\> Show-DbaDbList -SqlInstance sqlserver2014a

        Shows a GUI list of databases using Windows Authentication to connect to the SQL Server. Returns a string of the selected database.

    .EXAMPLE
        PS C:\> Show-DbaDbList -SqlInstance sqlserver2014a -SqlCredential $cred

        Shows a GUI list of databases using SQL credentials to connect to the SQL Server. Returns a string of the selected database.

    .EXAMPLE
        PS C:\> Show-DbaDbList -SqlInstance sqlserver2014a -DefaultDb master

        Shows a GUI list of databases using Windows Authentication to connect to the SQL Server. The "master" database will be selected when the lists shows. Returns a string of the selected database.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Title = "Select Database",
        [string]$Header = "Select the database:",
        [string]$DefaultDb,
        [switch]$EnableException
    )

    begin {
        try {
            Add-Type -AssemblyName PresentationFramework
        } catch {
            Stop-Function -Message "Windows Presentation Framework required but not installed"
            return
        }

        function Add-TreeItem {
            param (
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
            $image.Source = $dbicon
            $textblock.Text = $name
            $childitem.Tag = $name

            if ($name -eq $DefaultDb) {
                $childitem.IsSelected = $true
                $script:selected = $name
            }

            [void]$stackpanel.Children.Add($image)
            [void]$stackpanel.Children.Add($textblock)

            $childitem.Header = $stackpanel
            [void]$parent.Items.Add($childitem)
        }

        function Convert-b64toimg {
            param ($base64)

            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($base64)
            $bitmap.EndInit()
            $bitmap.Freeze()
            return $bitmap
        }

        $dbicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAFRSURBVDhPY/j//z9VMVZBSjCCgQZunFn6/8zenv+7llf83zA75/+6WTn/N80v+L93ddP/M/tnY2jAayDIoNvn5/5/cX/t/89vdv7/9fUQGIPYj2+t/H/xyJT/O1ZUoWjCaeCOxcX///48ShSeWhMC14jXwC9Xs/5/fzHr/6/PW+GaQS78/WH9/y+Pe8DyT3fYEmcgKJw+HHECawJp/vZ60f8v95v/fzgd8P/tVtn/L1cw/n+0iOH/7TlMxBkIigBiDewr9iVsICg2qWrg6qnpA2dgW5YrYQOX9icPAQPfU9PA2S2RRLuwMtaGOAOf73X+//FyGl4DL03jIM5AEFjdH/x//+Lo/1cOlP9/dnMq2MA3x/z/312l/P/4JNH/axoU/0/INUHRhNdAEDi+pQ1cZIFcDEpvoPCaVOTwf1Gjy/9ds5MxNGAYSC2MVZB8/J8BAGcHwqQBNWHRAAAAAElFTkSuQmCC"
        $foldericon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAHaSURBVDhPY/j//z9VMVZBSjBWQUowVkFKMApnzZL+/+gYWZ4YDGeANL95sun/j3fbwPjbm5X/Pz+cRLKhcAayq2B45YKe/8vndoHx4lltYLxgajMKhumHYRQDf37Yh4J/fNry//fb1f9/v1n6/8/Tqf//3O/6/+dO9f9fV4v+fzmV/v/L0aj/lflJQO1YDAS5AmwI1MvfPyAZ9KgbYtDlvP/fzyT9/3w45P+HPT7/z8+UwG0gyDvIBmIYBnQVyDCQq0CGPV9p8v94P/f/rKQwoHYsBs4HhgfIQJjLfr+YjdOwt5tt/z9eov1/fxf3/+ggD6B2HAaCXQYKM6hhv+81oYQXzLCXq03/P5qn/H9LE/9/LycroHYsBs7oq4EYCDIM6FVshr3Z4gg2DOS6O9Nk/q+sFvlvZawD1I7FwKldleC0h2zY9wuZEMP2+aMYdn+W/P/rE0T/zy+T+q+jJg/UjsXASe1l/z/cX/T/1dn8/492ePy/vc7s/82VOv8vLVT9f3yGwv89ffL/1zXL/l9dJwF2GciwaYVy/xVlxIDasRjY31Lyv7Uy+39ZTvz/1JiA/8Hejv8dLA3+62sqgTWJC/HixDAzQBjOoBbGKkgJxipICcYqSD7+zwAAkIiWzSGuSg0AAAAASUVORK5CYII="
        $dbatoolsicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAO9SURBVEhL3VVdTFNXHO9MzPTF+OzDeBixFdTMINIWsAUK3AIVkFvAIQVFRLYZKR8Wi1IEKV9DYB8PGFAyEx8QScySabYY5+I2JvK18iWISKGk0JGhLzA3+e2c29uHtpcvH/0lv9yennN+v3vO/3fOFb2fCAg4vXWPNOmMRJ745TtTSskqeElviGXJ0XtkWvjJkyGLPoFAVQZoe/NkX/n6Mh/ysu4Qy7WZdJAutxRW6zT6LcNQaE4LiGgREH4cibpCMNqzCIk9hbScEoSSZ0zKOa7fRxG/k5d1h8ukvO4a5ubmMT1jw5E0vZcBZWzqOTS3dcB8tRXZeRX4/v5DZH5uIu0Wrn8NEzaNDjgYoUPd120oMjViX2iql8H6ZFd8DzE7eFl3iOWpuyQydlh44kbJroilSd8RuQ+cqh7wC9Z+JJaxY8KTN0gp+5Yk9DaREzYhb5FOBwZFZ6LlZifKa5ux//AxYTHCvSEp8A9O5n77B6dwqXS119guZ+GrGq9jfn4eM7ZZxB/PdxN2UfOpHq3kRWq/uoE8Yx3u/fQLzhSYUdN0g+tfN126z0oxNj6BJz0Dq0b4E2UawuJzuPhKyZmKYr/AocgMrk37VzWRBLGRdE/psuXqk9wkT/GNUCJLWqS3By/rDh9FxjaSrnahiZ7cq8wCUzKImLIJqC+Ngbk4gmjjIKKKB6Aq7l+OLBmfVF0YnlQZR1p4eSd2y5IiyEr+oyJ0CwIi0gUNKAOPmnG04Q0utf+DHweWkFjjQOyVWajLpsCUPkeUcRgqAzE09Dfz8k64aqI9YcDziUk87bMgOCZL0CQ0ux2J9UtIbXyFwall/PD0NeLKrU6DkhGymj8RXtRDjU7x8k64TKpJQmi6bLOzSEgv8DYhNWMujiK+9jU0VQs4Vm/H2MwSOh4vcP+rii2cQVh+F+IqbRJe3glyReuoSFBUJtpu3eWulv2h3ueE1iOu0g5N9QL3jLk8jerbdrz59y1yGoYQUdSLsII/CLscIsD9UPrLUz4myXhBhWjCPMVdPBBnhMbsIAZzSDDbcOvRIhyLy6i4+Qyq82QFxECR9xjK/K5OXtodNHo+CsW2tagunbxADbK+sXP16Bv/G7lNQ8hpHEX21UGoDb/j8NmfoSzoNvCymwdTPvMotsKGB32LaL1H0mS0oOHOFLpH/0L3iAOF3/YSk4dgTBMh/JTNgdVbtzNl1il12UuSpHE+SRayTb0IL3yCMP2vUJKtUuh/szNNK8Jfxw3BZNpiMoGjiKPJm54Ffw8gEv0PQRYX7wDAUKEAAAAASUVORK5CYII="

        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # Create XAML form in Visual Studio, ensuring the ListView looks chromeless
        [xml]$xaml = "<Window
        xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='$Title' SizeToContent='WidthAndHeight' Background='#F0F0F0'
        WindowStartupLocation='CenterScreen' MaxHeight='600'>
    <Grid>
        <TreeView Name='treeview' Height='Auto' Width='Auto' Background='#FFFFFF' BorderBrush='#FFFFFF' Foreground='#FFFFFF' Margin='11,36,11,79'/>
        <Label x:Name='label' Content='$header' HorizontalAlignment='Left' Margin='15,4,10,0' VerticalAlignment='Top'/>
        <StackPanel HorizontalAlignment='Right' Orientation='Horizontal' VerticalAlignment='Bottom' Margin='0,50,10,30'>
        <Button Name='okbutton' Content='OK'  Margin='0,0,0,0' Width='75'/>
        <Label Width='10'/>
        <Button Name='cancelbutton' Content='Cancel' Margin='0,0,0,0' Width='75'/>
    </StackPanel>
</Grid>
</Window>"
        #second pushes it down
        # Turn XAML into PowerShell objects
        $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
        $window.icon = $dbatoolsicon

        $xaml.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name) -Scope Script }

        $childitem = New-Object System.Windows.Controls.TreeViewItem
        $textblock = New-Object System.Windows.Controls.TextBlock
        $textblock.Margin = "5,0"
        $stackpanel = New-Object System.Windows.Controls.StackPanel
        $stackpanel.Orientation = "Horizontal"
        $image = New-Object System.Windows.Controls.Image
        $image.Height = 20
        $image.Width = 20
        $image.Stretch = "Fill"
        $image.Source = $foldericon
        $textblock.Text = "Databases"
        $childitem.Tag = "Databases"
        $childitem.isExpanded = $true
        [void]$stackpanel.Children.Add($image)
        [void]$stackpanel.Children.Add($textblock)
        $childitem.Header = $stackpanel
        #Variable marked as unused by PSScriptAnalyzer
        $null = $treeview.Items.Add($childitem)

        try {
            $databases = $server.Databases.Name
        } catch {
            return
        }

        foreach ($database in $databases) {
            Add-TreeItem -Name $database -Parent $childitem -Tag $nameSpace
        }

        $okbutton.Add_Click( {
                $window.Close()
                $script:okay = $true
            })

        $cancelbutton.Add_Click( {
                $script:selected = $null
                $window.Close()
            })

        $window.Add_SourceInitialized( {
                [System.Windows.RoutedEventHandler]$Event = {
                    if ($_.OriginalSource -is [System.Windows.Controls.TreeViewItem]) {
                        $script:selected = $_.OriginalSource.Tag
                    }
                }
                $treeview.AddHandler([System.Windows.Controls.TreeViewItem]::SelectedEvent, $Event)
            })

        $null = $window.ShowDialog()
    }

    end {
        if ($script:selected.length -gt 0 -and $script:okay -eq $true) {
            return $script:selected
        }
    }
}