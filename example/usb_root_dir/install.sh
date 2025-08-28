#!/bin/sh

# USB 자동 실행 시스템 설치 스크립트
# 사용법: ./install.sh

echo "USB 자동 실행 시스템 설치를 시작합니다..."
echo "========================================="

# 1) 루트 파일시스템을 읽기/쓰기 모드로 재마운트
echo "1. 루트 파일시스템을 RW 모드로 재마운트..."
mount -o rw,remount /
if [ $? -eq 0 ]; then
    echo "   ✓ 루트 파일시스템 재마운트 성공"
else
    echo "   ✗ 루트 파일시스템 재마운트 실패"
    exit 1
fi

# 2) udev rule 파일 설치
echo "2. udev rule 파일 설치..."
if [ -f "install_files/99-usb-automount.rules" ]; then
    cp install_files/99-usb-automount.rules /etc/udev/rules.d/
    if [ $? -eq 0 ]; then
        echo "   ✓ udev rule 파일 설치 성공"
    else
        echo "   ✗ udev rule 파일 설치 실패"
        exit 1
    fi
else
    echo "   ✗ install_files/99-usb-automount.rules 파일이 없습니다"
    exit 1
fi

# 3) udev rule 업데이트
echo "3. udev rule 업데이트..."
udevadm control --reload-rules
udevadm trigger
if [ $? -eq 0 ]; then
    echo "   ✓ udev rule 업데이트 성공"
else
    echo "   ✗ udev rule 업데이트 실패"
    exit 1
fi

# 4) systemd service 파일 설치
echo "4. systemd service 파일 설치..."
if [ -f "install_files/usb-autorun@.service" ]; then
    cp install_files/usb-autorun@.service /etc/systemd/system/
    if [ $? -eq 0 ]; then
        echo "   ✓ systemd service 파일 설치 성공"
    else
        echo "   ✗ systemd service 파일 설치 실패"
        exit 1
    fi
else
    echo "   ✗ install_files/usb-autorun@.service 파일이 없습니다"
    exit 1
fi

# 5) systemd daemon-reload
echo "5. systemd daemon 재로드..."
systemctl daemon-reload
if [ $? -eq 0 ]; then
    echo "   ✓ systemd daemon 재로드 성공"
else
    echo "   ✗ systemd daemon 재로드 실패"
    exit 1
fi

# 6) zstd 패키지 확인 및 IPK 파일 설치
echo "6. zstd 패키지 확인 및 IPK 파일 설치..."

# zstd 명령어가 있는지 확인
if command -v zstd >/dev/null 2>&1; then
    echo "   ✓ zstd 패키지가 이미 설치되어 있습니다"
    echo "   ⚠ IPK 파일 설치를 건너뜁니다"
else
    echo "   ⚠ zstd 패키지가 설치되어 있지 않습니다"
    echo "   → zstd IPK 파일을 설치합니다..."
    
    # ipk_files 디렉토리에 zstd IPK 파일이 있는지 확인
    ZSTD_IPK=""
    for file in ipk_files/zstd_*.ipk; do
        if [ -f "$file" ]; then
            ZSTD_IPK="$file"
            break
        fi
    done
    
    if [ -n "$ZSTD_IPK" ]; then
        echo "   → zstd IPK 파일 발견: $(basename "$ZSTD_IPK")"
        echo "   → IPK 파일을 설치합니다..."
        opkg install "$ZSTD_IPK"
        if [ $? -eq 0 ]; then
            echo "   ✓ zstd IPK 패키지 설치 성공"
        else
            echo "   ⚠ zstd IPK 패키지 설치 실패 (수동 설치 필요)"
            echo "   → 수동으로 'opkg install $ZSTD_IPK' 실행하세요"
        fi
    else
        echo "   ✗ ipk_files/zstd_*.ipk 파일이 없습니다"
        echo "   → zstd 패키지를 수동으로 설치하세요: opkg update && opkg install zstd"
    fi
fi

echo ""
echo "========================================="
echo "USB 자동 실행 시스템 설치가 완료되었습니다!"
echo ""
echo "설치된 파일:"
echo "  - /etc/udev/rules.d/99-usb-automount.rules"
echo "  - /etc/systemd/system/usb-autorun@.service"
echo "  - zstd package (if installed)"
echo ""
echo "이제 USB 저장장치를 연결하면 자동으로 실행됩니다."
echo "테스트: USB 연결 후 'systemctl status usb-autorun@sd*.service' 확인"
