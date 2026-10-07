import '../../../theme/app_semantic_colors.dart';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/brand_assets.dart';
import '../../../shared/widgets/emoji_text.dart';
import '../../../theme/app_font_weights.dart';

class ProviderAvatar extends StatelessWidget {
  const ProviderAvatar({
    super.key,
    required this.providerKey,
    required this.displayName,
    this.size = 28,
    this.onTap,
  });

  final String providerKey;
  final String displayName;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cfg = context.watch<SettingsProvider>().getProviderConfig(
      providerKey,
      defaultName: displayName,
    );

    Widget avatar;
    final type = cfg.avatarType;
    final value = cfg.avatarValue;

    if (type == 'emoji' && value != null && value.isNotEmpty) {
      avatar = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: EmojiText(
          value.characters.take(1).toString(),
          fontSize: size * 0.5,
          optimizeEmojiAlign: true,
        ),
      );
    } else if (type == 'url' && value != null && value.isNotEmpty) {
      avatar = FutureBuilder<String?>(
        future: AvatarCache.getPath(value),
        builder: (ctx, snap) {
          final p = snap.data;
          if (p != null && File(p).existsSync()) {
            return ClipOval(
              child: Image(
                image: FileImage(File(p)),
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
          return ClipOval(
            child: Image.network(
              value,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _brandOrInitial(
                context,
                cfg.name.isNotEmpty ? cfg.name : displayName,
              ),
            ),
          );
        },
      );
    } else if (type == 'file' && value != null && value.isNotEmpty) {
      final fixed = SandboxPathResolver.fix(value);
      final f = File(fixed);
      if (f.existsSync()) {
        avatar = ClipOval(
          child: Image(
            image: FileImage(f),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } else {
        avatar = _brandOrInitial(
          context,
          cfg.name.isNotEmpty ? cfg.name : displayName,
        );
      }
    } else if (type == 'icon' && value != null && value.isNotEmpty) {
      // \u6821\u9A8C\u8D44\u6E90\u5728\u767D\u540D\u5355\u4E2D，\u9632\u6B62\u975E\u6CD5\u503C
      final asset = BrandAssets.selectableAssetOrNull(value);
      if (asset == null) {
        avatar = _brandOrInitial(
          context,
          cfg.name.isNotEmpty ? cfg.name : displayName,
        );
      } else {
        avatar = _assetAvatar(context, asset);
      }
    } else if (type == 'lobehub' && value != null && value.isNotEmpty) {
      avatar = _lobehubAvatar(
        context,
        value,
        cfg.name.isNotEmpty ? cfg.name : displayName,
      );
    } else {
      avatar = _brandOrInitial(
        context,
        cfg.name.isNotEmpty ? cfg.name : displayName,
      );
    }

    final portrait = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: cs.onSurface.withValues(alpha: isDark ? 0.24 : 0.12),
          width: 0.5,
        ),
      ),
      child: avatar,
    );

    final child = cfg.isOAuth
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              portrait,
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: size < 30 ? 7 : 10,
                  height: size < 30 ? 7 : 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        cfg.oauthCredentials == null ||
                            cfg.oauthCredentials!.requiresLogin
                        ? cs.error
                        : context.appColors.success,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          )
        : portrait;
    if (onTap == null) return child;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: child,
    );
  }

  Widget _brandOrInitial(BuildContext context, String name) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = BrandAssets.assetForName(name);
    if (asset == null) {
      return Container(
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
          style: TextStyle(
            color: cs.primary,
            fontWeight: AppFontWeights.emphasis,
            fontSize: size * 0.42,
          ),
        ),
      );
    }
    final mono = isDark && BrandAssets.assetNeedsDarkInvert(asset);
    return CircleAvatar(
      backgroundColor: cs.primary.withValues(alpha: isDark ? 0.18 : 0.1),
      child: asset.endsWith('.svg')
          ? SvgPicture.asset(
              asset,
              width: size * 0.7,
              height: size * 0.7,
              colorFilter: mono
                  ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn)
                  : null,
            )
          : Image.asset(
              asset,
              width: size * 0.7,
              height: size * 0.7,
              fit: BoxFit.contain,
              color: mono ? cs.onSurface : null,
              colorBlendMode: mono ? BlendMode.srcIn : null,
            ),
    );
  }

  // \u4F18\u5148\u5F69\u8272\u7248\u672C（{name}-color.svg），\u4E0D\u5B58\u5728\u5219\u56DE\u9000\u5355\u8272（{name}.svg）。
  // \u7528\u6237\u5DF2\u663E\u5F0F\u6307\u5B9A -color/-text \u53D8\u4F53\u65F6\u6309\u539F\u6837\u8BF7\u6C42。
  Future<String?> _resolveLobehubPath(String iconName) async {
    final n = iconName.trim().toLowerCase();
    if (n.isEmpty) return null;
    if (!n.endsWith('-color') && !n.endsWith('-text')) {
      final colored = await AvatarCache.getPath(
        BrandAssets.lobehubIconUrl('$n-color'),
      );
      if (colored != null) return colored;
    }
    return AvatarCache.getPath(BrandAssets.lobehubIconUrl(n));
  }

  // ' '\u540C' '\u6B65' '\u547D' '\u4E2D' '\u5DF2' '\u7F13' '\u5B58' '\u7684' r' LobeHub ' '\u56FE' '\u6807' '\u8DEF' '\u5F84' r'，' '\u547D' '\u4E2D' '\u5219' '\u53EF' '\u76F4' '\u63A5' '\u6E32' '\u67D3' r'、' '\u907F' '\u514D' r' FutureBuilder ' '\u95EA' '\u70C1' r'。
  // ' '\u955C' '\u50CF' r' _resolveLobehubPath ' '\u7684' '\u5F69' '\u8272' '\u4F18' '\u5148' r'/' '\u5355' '\u8272' '\u56DE' '\u9000' '\u987A' '\u5E8F' r'。
  String? _peekLobehubPath(String iconName) {
    final n = iconName.trim().toLowerCase();
    if (n.isEmpty) return null;
    if (!n.endsWith('-color') && !n.endsWith('-text')) {
      final colored = AvatarCache.peek(BrandAssets.lobehubIconUrl('$n-color'));
      if (colored != null) return colored;
    }
    return AvatarCache.peek(BrandAssets.lobehubIconUrl(n));
  }

  Widget _lobehubAvatar(
    BuildContext context,
    String iconName,
    String fallbackName,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = cs.primary.withValues(alpha: isDark ? 0.18 : 0.1);
    // ' '\u7F13' '\u5B58' '\u547D' '\u4E2D' '\u65F6' '\u540C' '\u6B65' '\u6E32' '\u67D3' r'，' '\u907F' '\u514D' '\u6BCF' '\u6B21' r' rebuild ' '\u90FD' '\u7ECF' '\u5386' r' FutureBuilder ' '\u7684' r' loading ' '\u6001' r'。
    final cached = _peekLobehubPath(iconName);
    if (cached != null) {
      return _lobehubTile(context, cached, bg);
    }
    return FutureBuilder<String?>(
      // ' '\u4F18' '\u5148' '\u5F69' '\u8272' '\u7248' '\u672C' r'，' '\u56DE' '\u9000' '\u5355' '\u8272' r'；' '\u590D' '\u7528' '\u5934' '\u50CF' '\u7F13' '\u5B58' r'（' '\u4E0B' '\u8F7D' '\u5E76' '\u7F13' '\u5B58' r' SVG，' '\u5931' '\u8D25' '\u8FD4' '\u56DE' r' null）
      future: _resolveLobehubPath(iconName),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return CircleAvatar(backgroundColor: bg);
        }
        final p = snap.data;
        if (p == null || !File(p).existsSync()) {
          return _brandOrInitial(context, fallbackName);
        }
        return _lobehubTile(context, p, bg);
      },
    );
  }

  Widget _lobehubTile(BuildContext context, String path, Color bg) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: bg,
      child: SvgPicture.file(
        File(path),
        width: size * 0.7,
        height: size * 0.7,
        fit: BoxFit.contain,
        // LobeHub ' '\u5355' '\u8272' '\u56FE' '\u6807' '\u7528' r' fill="currentColor"，' '\u6CE8' '\u5165' '\u524D' '\u666F' '\u8272' '\u4EE5' '\u9002' '\u914D' '\u660E' '\u6697' r'；
        // ' '\u5E26' r' -color ' '\u7684' '\u5F69' '\u8272' '\u56FE' '\u6807' '\u6709' '\u56FA' '\u5B9A' '\u586B' '\u5145' r'，' '\u4E0D' '\u53D7' '\u5F71' '\u54CD' r'
        theme: SvgTheme(currentColor: cs.onSurface),
        placeholderBuilder: (_) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _assetAvatar(BuildContext context, String asset) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSvg = asset.endsWith('.svg');
    final needsMono = isDark && BrandAssets.assetNeedsDarkInvert(asset);
    return CircleAvatar(
      backgroundColor: cs.primary.withValues(alpha: isDark ? 0.18 : 0.1),
      child: isSvg
          ? SvgPicture.asset(
              asset,
              width: size * 0.7,
              height: size * 0.7,
              colorFilter: needsMono
                  ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn)
                  : null,
            )
          : Image.asset(
              asset,
              width: size * 0.7,
              height: size * 0.7,
              fit: BoxFit.contain,
              color: needsMono ? cs.onSurface : null,
              colorBlendMode: needsMono ? BlendMode.srcIn : null,
            ),
    );
  }
}
