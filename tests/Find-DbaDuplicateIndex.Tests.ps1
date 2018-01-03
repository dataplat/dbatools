$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $sql = "create database [dbatools_dupeindex]"
        $server.Query($sql)
        $sql = "CREATE TABLE [dbatools_dupeindex].[dbo].[WABehaviorEvent](
                [BehaviorEventId] [smallint] NOT NULL,
                [ClickType] [nvarchar](50) NOT NULL,
                [Description] [nvarchar](512) NOT NULL,
                [BehaviorClassId] [tinyint] NOT NULL,
             CONSTRAINT [PK_WABehaviorEvent_BehaviorEventId] PRIMARY KEY CLUSTERED
            (
                [BehaviorEventId] ASC
            )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
            UNIQUE NONCLUSTERED
            (
                [ClickType] ASC
            )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
            ) ON [PRIMARY]


            CREATE UNIQUE NONCLUSTERED INDEX [IX_WABehaviorEvent_ClickType] ON [dbatools_dupeindex].[dbo].[WABehaviorEvent]
            (
                [ClickType] ASC
            )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

            ALTER TABLE [dbatools_dupeindex].[dbo].[WABehaviorEvent] ADD UNIQUE NONCLUSTERED
            (
                [ClickType] ASC
            )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
            "
        $server.Query($sql)
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database dbatools_dupeindex -Confirm:$false
    }

    Context "Gets back some results" {
        $results = Find-DbaDuplicateIndex -SqlInstance $script:instance1 -Database dbatools_dupeindex
        It "return at least two results" {
            $results.Count -ge 2 | Should Be $true
        }
    }
}