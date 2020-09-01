$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Column', 'Country', 'CountryCode', 'ExcludeTable', 'ExcludeColumn', 'SampleCount', 'KnownNameFilePath', 'PatternFilePath', 'ExcludeDefaultKnownName', 'ExcludeDefaultPattern', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $db = "dbatoolsci_piiscan"
        $sql = "CREATE TABLE [dbo].[Customer](
                    [CustomerID] [INT] IDENTITY(1,1) NOT NULL,
                    [Firstname] [VARCHAR](30) NULL,
                    [Lastname] [VARCHAR](50) NULL,
                    [FullName] [VARCHAR](100) NULL,
                    [Address] [VARCHAR](100) NULL,
                    [Zip] [VARCHAR](10) NULL,
                    [City] [VARCHAR](255) NULL,
                    [Randomtext] [VARCHAR](255) NULL
                ) ON [PRIMARY]
                GO
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (NULL, N'Lakin', N' Lakin', N'74262 Cormier Inlet', N'43515', N'Port Karine', N'6011295760226704')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Monserrate', N'Schmidt', N'Monserrate Schmidt', NULL, N'45269', N'New Gussie', N'eu3geQ2dINZWhLzs2eMEclvEFOVEYxQTI084fD91hP')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Delores', N'Fay', N'Delores Fay', N'209 Howe Club', N'89464', N'Homenickberg', NULL)
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Chelsea', N'Williamson', N'Chelsea Williamson', N'0733 Ebert Keys', N'10237-6424', N'Luciochester', N'5Q2K5TAequaevwlQjvGU72uvg')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Bobby', N'Rogahn', N'Bobby Rogahn', N'555 Koch Pine', N'54869-8872', N'South Duaneberg', N'tsg8idvGDY9LlV1zHYWOkOF2YfbLf2PDKsmkEJyGk9baOuQe20QNEKAOWokdbUBKiFb2JR57ApElNFoDz7Tplb891HxpyvEAIA1itXFk5SnogparaQOeblyhHbbbuPJfVdMnNfjLCIuDYT3LHgpSRAywb')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Nestor', N'Miller', N'Nestor Miller', N'406 Carmella Crescent', N'69506-4893', NULL, N'izEnz1yvPql2D1Z8SetQp18TCulOX5EgBXkw8M0sUixwMUBOmNUXMMIqAUUePTHTVeBQRD9fna5hDMhR3GBjkREYo35o2VMaLNLHtU6TOPKLQBXYNdkjryIeKMBYHVnBx5G0bJyjJRFFh2hXghLYLDSmeH7Rshm3CioV46XdPbKJ2d6SEOSAky04mtVDMQ1BFMd8Nw3jtHjJ3iu')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Alec', N'McGlynn', N'Alec McGlynn', N'2356 Reichert Center', N'34911', N'East Zeldashire', N'iVJgNoqbd9U3xEncT39Q')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Emma', NULL, N'Emma ', N'70006 Cicero Lakes', N'08860', N'Baileyburgh', N'MAAeD6gux9rUvDLgHd0q95SrnAumeXkParPHJaSDOUQcuzRzoIHVkcGQSi1cM3qJYMUeYdGGvxMopQ6XT48FpzE8U8YAjP0VEgnSPNKkcbAXArBcmdtS4UuziVt0pfxPH1')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Nikki', N'Considine', N'Nikki Considine', N'29654 Rahsaan Mall', NULL, N'Olafberg', N'wi0TWXJ3tU56NVpIGsJ74nygrfB')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Hoyt', N'Emard', N'Hoyt Emard', N'003 Emanuel Knoll', N'62758-5524', N'Westberg', N'rmiUUCQwiQDABgxB0IF54sPBYnUFn9o3grJekOqIQtGJsjBAnV')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (NULL, N'McDermott', N' McDermott', N'95711 Legros Rest', N'45315', N'East Clinton', N'6pLWfjPWurCzXCYaLHESU0FkxhSZq34EyjEcQlAHqTx3QTOhGk5UWDHgUAz8A0FAw7bN8Vtzh')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Ulices', N'Koch', N'Ulices Koch', NULL, N'46463-1917', N'Morarbury', N'qWChAn7GSSbjU0FNZaGNi5WGZHzBmogbKEdNOZcWEfW4BCIpDG23fTiu95r3YGtDL9JpW18a8')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Nelle', N'Considine', N'Nelle Considine', N'96329 Wallace Dam', N'37675-1997', N'West Isabell', NULL)
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Sigmund', N'Hackett', N'Sigmund Hackett', N'011 Hartmann Pine', N'99656-1407', N'Beierberg', N'CZWks1INDPQviDrLpqIF2MotAik3ykyzysAgIAWtJnBp7mFNiBDNFSwZKDTjQOot')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Devan', N'Graham', N'Devan Graham', N'842 Chandler Causeway', N'61932-6579', N'Nilsside', N'5KFeRNN58i9QoPK7xPkrWROMiFHj3rMFys3CP8h0KaRd8O976XJbKM3o626lfDbQFEr6VirzItQWaLNDGKnfSL4VyPGWb5Uh8aHEwclXFkCq6houoDPFq684KGHgLFxMJJX9djgDyzJHiNZrBlHHqp0ccN30FemaW0Rwuoqfxlg0')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Francisco', N'Keebler', N'Francisco Keebler', N'83377 Johnston Villages', N'42293-2572', NULL, N'C7n4Cjei9QL17kpAWd6EwOJq0ZinWNXPD9nsBFEQrlSevIseS3BEYXJYy6eNb0vw26y8768qJqml5F4rHdE2ms1Qzy4FB1OAZwlzkuhW5k5HKy32bWg7vDkJeSIIbDZSLWvItEhm6S7bxtfbFbEOURewmMvCWIUCvn5YduJGP3aNFimUMGda9k74R8wQjOAx8FQjyq7kC791QB1dzKZpFUCkqbgf82waCNP9CdwwI3Ibkfnqgs')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Dudley', N'Marquardt', N'Dudley Marquardt', N'31815 Joana Tunnel', N'94078-6324', N'Leraville', N'alY08PLXlqUB77jamQQ8AlPjEpR4vuFqcKESIs4H7YXisv4Omnra5mbYFPwT7QB0VEywCBB3WjbLyG0jvdSidEvZJQm36lJqx6xY6HlUVyoVlzz8Yn')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Gerda', NULL, N'Gerda ', N'772 Camille Parkway', N'95572-4102', N'Stokesshire', N'PqKNjqoeSXOseihOwUAFnBNkBk7YWaKdb5h9J5NFaDoX5Bktcx0dBBjoNzl9tzsSnLqiahfAh4FTmZp9aNWykGLJW3wjUN')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Clinton', N'McKenzie', N'Clinton McKenzie', N'92495 Alexander Groves', NULL, N'Kautzertown', N'km8PN4IQaRwhV5QDS4IQo5Y8u1gUKfNv2I9HOG7q74tDPlkwTCXb2uJoxauWXXf4dapn6iYl7rTuMvsiRUbisMDH8VkOmlCkYzAO66AKOLdKLpMbRledW7MAHRok8j9WYJFn5OmUuADQJ26Tii6agzx1W9goSpMELqVcUzgd9uTvD51OVFcZn9QzlOA6H7bfY9esg49Tb3aWQcx')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Roxane', N'Casper', N'Roxane Casper', N'53809 Goodwin Plains', N'50365', N'Port Kelli', N'1GsXt94TjqJYfDY2bSCSUd3V1x8DbF39I3MQ487NQMRZywzIDWFVz0XYNH65bAROxKpm1i7cVYbhvdwE8z9pahKSgXdwcbMp5dBYgnQvYCaKZQCJlB7LBCOqaHgdeKaTmVmsMHxUSNAHg')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (NULL, N'Zemlak', N' Zemlak', N'0844 Lambert Center', N'85162', N'South Donatobury', N'Dk7Ndm2XbgjaOQ')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Mina', N'McLaughlin', N'Mina McLaughlin', NULL, N'19784-7861', N'East Barbara', N'LZ6lGHG1ibBsbX5B4QYbKlgTqG4pJWAYauyYTHe13Zd5sKz63mmQyepATm49NrrwLMsRygRwM7iVilAQh7vxJTA5f8fGNenLHRtQrSHWEZeA5DrHWo2P54W1lxLzblTIUGoB1UyyAJ2UPa9LQHUylHQM4CF4giVtgFQzp0QbZDpwccmlx9SEAuwm0LGzpDsrXJNjtKw01SJRrtK2qtHgz')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Drake', N'Swift', N'Drake Swift', N'7319 Hane Freeway', N'43087-6867', N'O''Reillyside', NULL)
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Justus', N'Altenwerth', N'Justus Altenwerth', N'780 Seth Mountain', N'07559-2537', N'South Cyrusview', N'CHOjaDIbNQh0y9fbUGccV5wcWHjLV2k6DmSv2H1GqaeZDeZGoTx7lz8HkLxDu7pVFkxmrUjnOFVU1GIRSNwbEnUenlkqkylsUsusRMoEKksQOoPOcQVRLnqsAt8fJ2dqtC9Jlq9fy2Bu4ez9GFoENERGbc2yOj4ShcwmogCWQPtTW6xv39JdOJNZUDHjyK')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Hipolito', N'Ferry', N'Hipolito Ferry', N'274 Samir Road', N'47919', N'Ashtonfurt', N'EPJ0dIzHBVItxfpeVdSGOQojamVQOWSBF2fVOgPPCkV91TdRRgmRwi1YBA01WT3PcgYF9DzOxdeD5orqid8IJbfwarunqY2Srf7U5HRnQItsey2mjJSSVvgabBFSjlyJkvmZr')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Kailyn', N'Harvey', N'Kailyn Harvey', N'363 Mireille Spur', N'06019', NULL, N'97SEc9eEjTiSld5LohwbDfrpi3tcgRDaxq0tY0IwQw19OJAvlCC8X6C3PDviQbyCphv4mLXyIauhnsLJD80OpFnBY6OvEzQO8zTGoFiKPdzXLuQx2WPRkTnT43gq7C3juQiYIeu7Zq8lgAZDqqDST8DolaMvy2MnkpC5l1ZXCS24VcNEdNaQ8kzvm4NIB9I7NVa074ryBPqbgJDjwirV26o90hTrorwCj4q9cXGjvLpt4yp')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Llewellyn', N'Kerluke', N'Llewellyn Kerluke', N'500 Boehm River', N'10113-8813', N'North Kenya', N'hAqR5fB1g0UfcUxZIDbXQ9vBe9gHeu7wMRKwYaL5I8ejzeqdEwTafV4ifZM584XW2xDvjabI1goR5lc9SdcSK6r0WCq9yP6OlsrbL53Duli9Gmn4XMm41fl6gMIQUckmjKGN4ayXkJxzYrtJpwlVCbWggv4')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Waylon', NULL, N'Waylon ', N'96507 Torey Street', N'47277', N'Lake Elyseshire', N'x0yUhYAGJfAB7Zey2Bx3PwzIdrEyunfOxVwCNlShqdBQX8XCNxpx5fVaB0R0tblvaVdmDLVRTpML5SUeDcU78RTr9vbWE1Xo2fQc4L8bMIOQDjfTf')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Lilla', N'Hills', N'Lilla Hills', N'2159 Alfreda Springs', NULL, N'Port Ivorybury', N'ZbSk2dSuAdcYZpsR1EF7NSy9jyZBOvXofAqRwCEoI37o97w3sqvw6AghMSaDorQfqYTz9KuzarzTUjalc6jx9AsOtifOBa9qn28kn64R66vObwwCSZBritfZGef0FQ79riG2l07fcBBdfNN7VM6MJSi4WjNj1dmp8vw30Dr21wpQ1cT3Bie3UvAJ9Mgbm')
                INSERT [dbo].[Customer] ([Firstname], [Lastname], [FullName], [Address], [Zip], [City], [Randomtext]) VALUES (N'Reese', N'Farrell', N'Reese Farrell', N'12307 Gottlieb Shoal', N'44074', N'Prohaskachester', N'tEN4W3nxqPciqAP7aLRaWIQJohGKwLBhFa6QBYE034eyTembwWziaRlUYdQPwNbPn4MpE8Gmh1h1Es0j4FnJmthXYl2xhYDp3ykYC6HxpnbiKuqGnHU1ACD4XYAsgjesx18fhcR880t8r8nE5wkKeMZB5qaNFoqgiTVTvkzk0W3JiENZL5xU9EoVbGj1cdCTJmZHmEjU69TrTqsBMlbK0GhOFaRZbHiWtja5OfMhWMX9U6bVnRo0b22cf')
                "

        New-DbaDatabase -SqlInstance $script:instance2 -Name $db
        Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query $sql
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $db -Confirm:$false
    }

    Context "Command works" {
        It "starts with the right data" {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "SELECT * FROM Customer WHERE FirstName = 'Delores'" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "SELECT * FROM Customer WHERE RandomText = '6011295760226704'" | Should -Not -Be $null
        }

        It "returns the proper output" {

            $results = Invoke-DbaDbPiiScan -SqlInstance $script:instance2 -Database $db

            $results.Count | Should -Be 7

            $results."PII-Name" | Should -Contain "Creditcard Discover"
        }

    }
}