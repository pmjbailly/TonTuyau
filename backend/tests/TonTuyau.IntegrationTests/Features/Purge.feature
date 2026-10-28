@elasticsearch @sync @api @youtube
Feature: Purging a channel's videos, and downloading them again with other settings
  A purge (2.2.1, the task purgeVideos) deletes videos of one channel from TonTuyau: some of them, or all of them. Each
  goes with its file, its thumbnail, its comments and its failed download; the channel and its subscription stay.
  Nothing is asked of YouTube: a later full sync of the channel downloads them again. "Download everything" of one
  channel takes yt-dlp's format and the retry without the cookie this once, the YouTube page's settings left as they
  are. yt-dlp is a fake here.

  Background:
    Given TubeArchivist has the channel "alpha" with 2 videos
    And TubeArchivist is subscribed to the channel "alpha"
    And the backend is ready
    And a first import has run
    And I logged in as the admin
    And there's no pause between videos

  Scenario: The videos picked are purged, files and all; the others stay
    Given YouTube has the video "alpha-04": the title "À purger", 3 views
    When I download "alpha-04___" with my session
    Then the latest run ends succeeded within 30 seconds
    And the media folder has the file of the video "alpha-04" with 4096 bytes
    When I purge the videos "alpha-04, alpha-01" of the channel "alpha" with my session
    Then the response status is 202
    And "task" is "purgeVideos"
    And "target" is "UCalpha_________________"
    And the latest run ends succeeded within 30 seconds
    And the latest run's "counts.purged" is "2" within 5 seconds
    And the latest run's notes mention "2 videos purged"
    And TonTuyau doesn't have the video "alpha-04"
    And TonTuyau doesn't have the video "alpha-01"
    And TonTuyau has the video "alpha-02"
    And the index doesn't have the video "alpha-04"
    And the media folder doesn't have the file of the video "alpha-04"

  Scenario: The whole channel is purged, then its full sync downloads its videos again
    When I purge the channel "alpha" with my session
    Then the response status is 202
    And the latest run ends succeeded within 30 seconds
    And the latest run's "counts.purged" is "2" within 5 seconds
    And TonTuyau doesn't have the video "alpha-01"
    And TonTuyau doesn't have the video "alpha-02"
    Given YouTube has the videos "alpha-01"
    And YouTube lists "alpha-01" on the videos tab of the channel "alpha"
    When I download everything of the channel "alpha" with my session
    Then the latest run ends succeeded within 60 seconds
    And the media folder has the file of the video "alpha-01" with 4096 bytes

  Scenario: On the command line, a channel is purged whole
    When I run "tontuyau youtube purge UCalpha_________________"
    Then the command exits with code 0
    And the output mentions "purged    2 videos"
    And TonTuyau doesn't have the video "alpha-01"

  Scenario: A video of another channel, or one not in the library, isn't purged
    When I purge the videos "beta-01, alpha-09" of the channel "alpha" with my session
    Then the response status is 202
    And the latest run ends succeeded within 30 seconds
    And the latest run's "counts.purged" is "0" within 5 seconds
    And TonTuyau has the video "alpha-01"

  Scenario Outline: A purge the API doesn't take is a 400
    When I send POST "<path>" with my session
    Then the response status is 400

    Examples:
      | path                                                                                  |
      | /api/admin/tasks/purgeVideos/runs                                                     |
      | /api/admin/tasks/purgeVideos/runs?target=nope                                         |
      | /api/admin/tasks/purgeVideos/runs?target=UCalpha_________________&videos=nope         |
      | /api/admin/tasks/purgeVideos/runs?target=UCalpha_________________&videos=,            |
      | /api/admin/tasks/refreshChannel/runs?target=UCalpha_________________&videos=alpha-01___ |

  Scenario: A channel the library doesn't have isn't purged
    When I purge the channel "nobody" with my session
    Then the response status is 409
    And "detail" mentions "No channel"

  Scenario: "Download everything" with a format: its downloads take it, this once
    Given YouTube has the videos "alpha-03"
    And YouTube lists "alpha-03, alpha-02, alpha-01" on the videos tab of the channel "alpha"
    When I download everything of the channel "alpha" with "format=398%2B251" with my session
    Then the response status is 202
    And the latest run ends succeeded within 60 seconds
    And yt-dlp was asked for the format "398+251" for the video "alpha-03"

  Scenario: "Download everything" without the retry without the cookie: a format matching none isn't downloaded
    Given YouTube, signed in, says of the video "alpha-05": "ERROR: [youtube] alpha-05___: Requested format is not available. Use --list-formats for a list of available formats"
    And I sent the YouTube cookie "SIGNED_IN" with my session
    And YouTube lists "alpha-05, alpha-02, alpha-01" on the videos tab of the channel "alpha"
    When I download everything of the channel "alpha" with "retryWithoutCookie=false" with my session
    Then the response status is 202
    And the latest run ends succeeded within 60 seconds
    And TonTuyau doesn't have the video "alpha-05"
    And the latest run's notes mention "(alpha-05___) not downloaded: Requested format is not available"

  Scenario Outline: Download settings go with "Download everything" of one channel only
    When I send POST "<path>" with my session
    Then the response status is 400

    Examples:
      | path                                                                     |
      | /api/admin/tasks/youTubeFullSync/runs?format=best                        |
      | /api/admin/tasks/youTubeFullSync/runs?retryWithoutCookie=false           |
      | /api/admin/tasks/youTubeSync/runs?retryWithoutCookie=true                |
      | /api/admin/tasks/downloadVideo/runs?target=alpha-09___&retryWithoutCookie=true |
