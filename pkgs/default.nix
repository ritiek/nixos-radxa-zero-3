{ pkgs }:

let
  # Rockchip MPP/RGA userspace at the commits jellyfin-ffmpeg's own builder
  # pins (builder/scripts.d/50-rkmpp.sh, 50-rkrga.sh).
  rkMirrors = rev: hash: pkgs.fetchFromGitHub {
    owner = "nyanmisaka";
    repo = "rk-mirrors";
    inherit rev hash;
  };
in
rec {
  # Mainline U-Boot. It reads the board ID from SARADC channel 1 and picks
  # rk3566-radxa-zero-3w.dtb or -3e.dtb itself, so one build boots both.
  uboot = pkgs.ubootRadxaZero3W.overrideAttrs (old: {
    # Rockchip's BL31 (as Armbian uses): the vendor kernel needs its SIP
    # services, mainline TF-A hangs it.
    env = old.env // { BL31 = pkgs.rkbin.BL31_RK3568; };
    # The root (and /boot with it) is btrfs.
    extraConfig = (old.extraConfig or "") + ''
      CONFIG_FS_BTRFS=y
      CONFIG_CMD_BTRFS=y
    '';
  });

  # VPU (video decode/encode) userspace.
  rockchip-mpp = pkgs.stdenv.mkDerivation {
    pname = "rockchip-mpp";
    version = "jellyfin-a9380ef";
    src = rkMirrors "a9380ef333102ac318628f83b5f7a460d377749e" "sha256-W18KrNdd1HNcubDv0K+CmAEdbXiqB5y0ECb0FUefUrk=";
    nativeBuildInputs = [ pkgs.cmake ];
    # Its .pc files do ${prefix}/@CMAKE_INSTALL_LIBDIR@, so keep the dirs relative.
    cmakeFlags = [ "-DBUILD_TEST=OFF" "-DCMAKE_INSTALL_LIBDIR=lib" "-DCMAKE_INSTALL_INCLUDEDIR=include" ];
  };

  # 2D scaler/converter userspace.
  librga = pkgs.stdenv.mkDerivation {
    pname = "librga";
    version = "jellyfin-1d330cc";
    src = rkMirrors "1d330cc28551943bed3380261a5a9c6fbd58ff53" "sha256-EO/YvkyaAgIyAZQJjXa8b5SEgCo4vfDpYoeKcJH1n4o=";
    nativeBuildInputs = with pkgs; [ meson ninja pkg-config ];
    mesonFlags = [ "-Dcpp_args=-fpermissive" "-Dlibdrm=false" "-Dlibrga_demo=false" ];
  };

  # ffmpeg with h264_rkmpp/hevc_rkmpp encoders, rkmpp hwaccel and vpp_rkrga.
  jellyfin-ffmpeg-rockchip = pkgs.jellyfin-ffmpeg.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ rockchip-mpp librga ];
    configureFlags = old.configureFlags ++ [ "--enable-rkmpp" "--enable-rkrga" ];
  });

  # NPU runtime (closed source) for RKNN models.
  librknnrt = pkgs.stdenv.mkDerivation {
    pname = "librknnrt";
    version = "2.3.2";
    src = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/airockchip/rknn-toolkit2/v2.3.2/rknpu2/runtime/Linux/librknn_api/aarch64/librknnrt.so";
      hash = "sha256-0x/BnIW4X2CRsr0PavnZYtUmSk5BC/tTZALskrrHOOg=";
    };
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    installPhase = "install -Dm755 $src $out/lib/librknnrt.so";
  };
}
