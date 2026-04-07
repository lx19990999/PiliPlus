import 'package:PiliPlus/common/widgets/scroll_physics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/member.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/member/contribute_type.dart';
import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models_new/space/space_archive/data.dart';
import 'package:PiliPlus/models_new/space/space_archive/episodic_button.dart';
import 'package:PiliPlus/models_new/space/space_archive/item.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class MemberVideoCtr
    extends CommonListController<SpaceArchiveData, SpaceArchiveItem>
    with ReloadMixin {
  MemberVideoCtr({
    required this.type,
    required this.mid,
    required this.seasonId,
    required this.seriesId,
    this.username,
    this.title,
  }) : isVideo = type == .video;

  final ContributeType type;
  final bool isVideo;
  int? seasonId;
  int? seriesId;
  final int mid;
  late ArchiveOrderTypeApp order = .pubdate;
  late ArchiveSortTypeApp sort = .desc;
  int? count;
  int? next;
  EpisodicButton? episodicButton;
  final String? username;
  final String? title;

  String? firstAid;
  String? lastAid;
  String? fromViewAid;
  RxBool isLocating = false.obs;
  bool isLoadPrevious = false;
  bool? hasPrev;

  @override
  Future<void> onRefresh() async {
    if (isLocating.value) {
      if (hasPrev == true) {
        isLoadPrevious = true;
        await queryData();
      }
    } else {
      isLoadPrevious = false;
      firstAid = null;
      lastAid = null;
      next = null;
      isEnd = false;
      page = 0;
      await queryData();
    }
  }

  @override
  void onInit() {
    super.onInit();
    if (isVideo) {
      fromViewAid = Get.parameters['from_view_aid'];
    }
    page = 0;
    queryData();
  }

  @override
  bool customHandleResponse(
    bool isRefresh,
    Success<SpaceArchiveData> response,
  ) {
    final data = response.response;
    episodicButton = data.episodicButton;
    next = data.next;
    if (page == 0 || isLoadPrevious) {
      hasPrev = data.hasPrev;
    }
    if (page == 0 || !isLoadPrevious) {
      if ((isVideo ? data.hasNext == false : data.next == 0) ||
          data.item.isNullOrEmpty) {
        isEnd = true;
      }
    }
    count = type == .season ? data.item?.length : data.count;
    if (page != 0) {
      if (loadingState.value case Success(:final response)) {
        data.item ??= <SpaceArchiveItem>[];
        if (isLoadPrevious) {
          data.item!.addAll(response!);
        } else {
          data.item!.insertAll(0, response!);
        }
      }
    }
    firstAid = data.item?.firstOrNull?.param;
    lastAid = data.item?.lastOrNull?.param;
    isLoadPrevious = false;
    loadingState.value = Success(data.item);
    return true;
  }

  @override
  Future<LoadingState<SpaceArchiveData>> customGetData() =>
      MemberHttp.spaceArchive(
        type: type,
        mid: mid,
        aid: isVideo
            ? isLoadPrevious
                  ? firstAid
                  : lastAid
            : null,
        order: isVideo ? order : null,
        sort: isVideo
            ? isLoadPrevious
                  ? .asc
                  : null
            : sort,
        pn: type == .charging ? page : null,
        next: next,
        seasonId: seasonId,
        seriesId: seriesId,
        includeCursor: isLocating.value && page == 0,
      );

  void queryBySort() {
    if (isLoading) return;
    if (isVideo) {
      isLocating.value = false;
      order = order == .pubdate ? .click : .pubdate;
    } else {
      sort = sort == .desc ? .asc : .desc;
    }
    onReload();
  }

  Future<void> toViewPlayAll() async {
    final episodicButton = this.episodicButton!;
    if (episodicButton.text == '继续播放' &&
        episodicButton.uri?.isNotEmpty == true) {
      final params = Uri.parse(episodicButton.uri!).queryParameters;
      String? oid = params['oid'];
      if (oid != null) {
        final bvid = IdUtils.av2bv(int.parse(oid));
        final cid = await SearchHttp.ab2c(aid: oid, bvid: bvid);
        if (cid != null) {
          PageUtils.toVideoPage(
            aid: int.parse(oid),
            bvid: bvid,
            cid: cid,
            extraArguments: {
              'sourceType': SourceType.archive,
              'mediaId': seasonId ?? seriesId ?? mid,
              'oid': oid,
              'favTitle':
                  '$username: ${title ?? episodicButton.text ?? '播放全部'}',
              if (seriesId == null) 'count': ?count,
              if (seasonId != null || seriesId != null)
                'mediaType': params['page_type'],
              'desc': params['desc'] == '1',
              'sortField': params['sort_field'],
              'isContinuePlaying': true,
            },
          );
        }
      }
      return;
    }

    if (loadingState.value case Success(:final response)) {
      if (response == null || response.isEmpty) return;

      for (SpaceArchiveItem element in response) {
        if (element.cid == null) {
          continue;
        } else {
          bool desc = seasonId != null ? false : true;
          desc =
              (seasonId != null || seriesId != null) &&
                  (isVideo ? order == .click : sort == .asc)
              ? !desc
              : desc;
          PageUtils.toVideoPage(
            bvid: element.bvid,
            cid: element.cid!,
            cover: element.cover,
            title: element.title,
            extraArguments: {
              'sourceType': SourceType.archive,
              'mediaId': seasonId ?? seriesId ?? mid,
              'oid': IdUtils.bv2av(element.bvid!),
              'favTitle':
                  '$username: ${title ?? episodicButton.text ?? '播放全部'}',
              if (seriesId == null) 'count': ?count,
              if (seasonId != null || seriesId != null)
                'mediaType': Uri.parse(
                  episodicButton.uri!,
                ).queryParameters['page_type'],
              'desc': desc,
              if (isVideo) 'sortField': order == .click ? 2 : 1,
            },
          );
          break;
        }
      }
    }
  }

  Future<void> downloadAll() async {
    // 获取下载服务实例
    final downloadService = Get.find<DownloadService>();
    await downloadService.waitForInitialization;

    // 保存当前状态
    final savedNext = next;
    final savedLastAid = lastAid;
    final savedFirstAid = firstAid;
    final savedIsLoadPrevious = isLoadPrevious;
    final savedPage = page;

    try {
      // 收集所有视频
      List<SpaceArchiveItem> allVideos = [];
      int? currentNext = savedNext;
      String? currentLastAid = savedLastAid;
      int currentPage = savedPage;
      bool hasMore = true;

      // 显示加载对话框（只显示一次）
      SmartDialog.showLoading(msg: '正在加载所有视频列表...');

      // 先添加当前已加载的视频
      if (loadingState.value case Success(:final response)) {
        if (response != null && response.isNotEmpty) {
          allVideos.addAll(response);
          // 如果已经加载了数据，从下一页开始
          if (type == ContributeType.charging) {
            currentPage = savedPage + 1;
          }
        }
      }

      // 循环加载所有页面的数据
      while (hasMore) {
        // 更新分页参数
        if (type == ContributeType.video) {
          lastAid = currentLastAid;
          next = null; // video 类型使用 aid 分页，不使用 next
          page = 0; // video 类型不使用页码
        } else if (type == ContributeType.charging) {
          page = currentPage;
          next = null;
          lastAid = null;
        } else {
          next = currentNext;
          lastAid = null;
          page = 0;
        }
        isLoadPrevious = false;

        // 加载下一页数据
        final result = await customGetData();
        if (result case Success(:final data)) {
          if (data.item != null && data.item!.isNotEmpty) {
            allVideos.addAll(data.item!);
            currentNext = data.next;
            currentLastAid = data.item?.lastOrNull?.param;
            
            // 判断是否还有更多数据
            if (type == ContributeType.video) {
              hasMore = data.hasNext == true;
            } else if (type == ContributeType.charging) {
              hasMore = data.next != null && data.next != 0;
              if (hasMore) {
                currentPage++;
              }
            } else {
              hasMore = data.next != null && data.next != 0;
            }
          } else {
            hasMore = false;
          }
        } else {
          hasMore = false;
        }
      }

      // 恢复状态
      next = savedNext;
      lastAid = savedLastAid;
      firstAid = savedFirstAid;
      isLoadPrevious = savedIsLoadPrevious;
      page = savedPage;

      if (allVideos.isEmpty) {
        SmartDialog.dismiss();
        SmartDialog.showToast('没有可下载的视频');
        return;
      }

      // 定义画质优先级列表（按照要求：1080p -> 720p -> 480p）
      final qualityPriorities = [
        VideoQuality.high1080, // 1080P 高清
        VideoQuality.high720, // 720P 准高清
        VideoQuality.clear480, // 480P 标清
      ];

      int successCount = 0;
      int totalCount = allVideos.where((item) => item.cid != null).length;

      // 更新消息，不关闭对话框
      SmartDialog.showLoading(msg: '准备离线 (${successCount}/${totalCount})');

      for (SpaceArchiveItem item in allVideos) {
        if (item.cid == null) {
          continue;
        }

        try {
          // 获取视频详情以获取分P信息
          var videoDetailRes = await VideoHttp.videoIntro(bvid: item.bvid!);
          if (videoDetailRes case Success(:var response)) {
            var videoDetail = response;
            var pages = videoDetail.pages;

            // 如果有多个分P，对每个分P进行下载
            if (pages != null && pages.isNotEmpty) {
              for (var page in pages) {
                // 尝试按优先级下载
                for (var quality in qualityPriorities) {
                  try {
                    // 创建Part对象
                    Part part = Part(
                      cid: page.cid,
                      page: page.page,
                      from: page.from,
                      part: page.part,
                      duration: page.duration,
                      vid: page.vid,
                    );

                    // 调用下载方法
                    downloadService.downloadVideo(
                      part,
                      videoDetail,
                      null,
                      quality,
                    );
                    successCount++;
                    // 只更新消息，不关闭对话框
                    SmartDialog.showLoading(
                      msg: '已添加到下载队列 (${successCount}/${totalCount})',
                    );
                    break; // 成功添加到下载队列后跳出质量选择循环
                  } catch (e) {
                    continue; // 尝试下一个质量
                  }
                }
              }
            } else {
              // 单个视频的情况
              for (var quality in qualityPriorities) {
                try {
                  Part part = Part(
                    cid: item.cid,
                    page: 1,
                    from: 'local',
                    part: item.title,
                    duration: item.duration,
                  );

                  downloadService.downloadVideo(part, null, null, quality);
                  successCount++;
                  // 只更新消息，不关闭对话框
                  SmartDialog.showLoading(
                    msg: '已添加到下载队列 (${successCount}/${totalCount})',
                  );
                  break; // 成功添加到下载队列后跳出质量选择循环
                } catch (e) {
                  continue; // 尝试下一个质量
                }
              }
            }
          }
        } catch (e) {
          print('下载视频出错: ${item.title}, 错误: $e');
          continue;
        }
      }

      SmartDialog.dismiss();
      SmartDialog.showToast('离线任务已添加完成: $successCount/$totalCount');
    } catch (e) {
      // 恢复状态
      next = savedNext;
      lastAid = savedLastAid;
      firstAid = savedFirstAid;
      isLoadPrevious = savedIsLoadPrevious;
      page = savedPage;
      
      SmartDialog.dismiss();
      SmartDialog.showToast('加载视频列表失败: $e');
    }
  }

  @override
  Future<void> onReload() {
    reload = true;
    isLocating.value = false;
    return super.onReload();
  }
}
