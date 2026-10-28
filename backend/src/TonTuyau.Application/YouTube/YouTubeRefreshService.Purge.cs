using System.Globalization;
using Microsoft.Extensions.Logging;
using TonTuyau.Application.Library;
using TonTuyau.Application.Store;
using TonTuyau.Application.Sync;

namespace TonTuyau.Application.YouTube;

/// <summary>
/// The purge (2.2.1): videos of one channel deleted from TonTuyau, one at a time: the file, the thumbnail and its resized
/// versions, the failed download, then the video (its comments, state on YouTube and keyframes go with it) and its copy
/// in the index. Nothing is asked of YouTube: a later full sync of the channel downloads them again, an import brings
/// back TubeArchivist's.
/// </summary>
public sealed partial class YouTubeRefreshService
{
    private const double BytesPerGb = 1024d * 1024 * 1024;

    /// <summary>What a purge deletes: the videos asked for that are the channel's, or all of them; latest first.</summary>
    /// <param name="asked">The videos asked for; none: the whole channel.</param>
    private async Task<List<string>> PurgeWorkAsync(
        string channelId,
        IReadOnlyList<string> asked,
        CancellationToken cancellationToken)
    {
        IReadOnlyList<VideoSummary> ofChannel = await videos
            .FindByChannelsAsync([channelId], cancellationToken)
            .ConfigureAwait(false);
        HashSet<string> wanted = new(asked, StringComparer.Ordinal);
        return
        [
            .. ofChannel
                .Where(v => wanted.Count == 0 || wanted.Contains(v.Id))
                .OrderByDescending(v => v.Downloaded)
                .Select(v => v.Id),
        ];
    }

    /// <summary>Deletes one video of the library, with its file; one gone meanwhile is left.</summary>
    /// <returns>The bytes its file freed; 0 when it had none on the share.</returns>
    private async Task<long> PurgeOneAsync(string videoId, RunContext context)
    {
        CancellationToken ct = context.CancellationToken;
        if (await videos.GetStoredAsync(videoId, ct).ConfigureAwait(false) is not { } stored)
        {
            return 0;
        }

        Video video = stored.Video;
        bool deleted;
        try
        {
            deleted = media.Delete(video.MediaPath);
        }
        catch (IOException ex)
        {
            // Its file stays, so does the video: nothing is lost track of.
            context.Note($"\"{video.Title}\" ({videoId}) not purged: its file can't be deleted ({ex.Message}).");
            LogNotPurged(videoId, ex.Message);
            return 0;
        }

        if (LibraryPaths.IsArtPath(video.ThumbnailPath))
        {
            art.Delete(video.ThumbnailPath);
        }

        await downloadFailures.RemoveAsync(videoId, ct).ConfigureAwait(false);
        await videos.DeleteAsync([videoId], ct).ConfigureAwait(false);
        context.Count(c => c with { Purged = c.Purged + 1 });
        LogPurged(videoId, video.Title, deleted);
        return deleted ? video.MediaSize : 0;
    }

    private static void NotePurged(long freed, RunContext context)
    {
        int purged = context.Run.Counts.Purged;
        context.Note(string.Create(
            CultureInfo.InvariantCulture,
            $"{purged} {(purged == 1 ? "video" : "videos")} purged, {freed / BytesPerGb:0.##} GB freed on the videos folder's disk. A full sync of the channel downloads them again."));
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "{VideoId} purged: \"{Title}\" (its file deleted: {File}).")]
    private partial void LogPurged(string videoId, string title, bool file);

    [LoggerMessage(Level = LogLevel.Warning, Message = "{VideoId} not purged: its file can't be deleted: {Reason}")]
    private partial void LogNotPurged(string videoId, string reason);
}
