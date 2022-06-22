#!/bin/bash
function check_user (){
  user=$(whoami)
  if [ "$user" != "root" ] ; then
    printf "execute como root. Saindo com status de erro"
    exit 1
  else
    check_filesystem
  fi
}
function check_filesystem(){
  umount /boot/efi
  umount /boot
    if [ $? -eq 32 ] ; then
        if  [ "$rootfilesystem" !=  "btrfs" ] ||  [ "$subvol_to_move" == "$nonevalue"  ]; then
          printf "use somente em um root inteiramente btrfs, dentro de um subvolume. Saindo com status de erro"
          exit 1
        else
          printf "sistema de arquivos conferido, testando dependencias" &&\
          check_deps
        fi
    else
      printf "use a raiz inteira, em um único subvolume btrfs. /boot separado incompatível. Saindo com status de erro"
      exit 1
    fi
}
function check_deps (){
  if [ -f /etc/grub.d/41_snapshots-btrfs ] && command -v grub-install && command -v arch-chroot ; then
    printf "dependencias conferidas, adaptando arquivos" &&\
        manage_files
      else
        printf "
        alguma das dependências não foi satisfeita.
        verifique sua instalação
        essa ferramenta precisa de
        grub
        grub-btrfs
        arch-install-scripts
        saindo com status de erro

"
        exit 1
  fi
}
function manage_files(){
  if [ -f usr/local/sbin/commit-root.original ] && [ -f usr/local/sbin/commit-root.original ] && [ -f usr/local/sbin/commit-root.original ]; then
    sed "s|name_block_device_here|"$rootblock"|g" usr/local/sbin/base-manager.original > usr/local/sbin/base-manager &&\
    sed "s|name_block_device_here|"$rootblock"|g" usr/local/sbin/pac-base.original > usr/local/sbin/pac-base &&\
    sed "s|name_block_device_here|"$rootblock"|g" usr/local/sbin/commit-root.original > usr/local/sbin/commit-root &&\
    last_chance
  else
    printf "
    os scripts de implementação não estão nos locais corretos. Clone o repositório novamente,
    ou edite o script de instalação para refletir corretamente suas mudanças. Saindo com status de erro"
    exit 1
  fi
}
function last_chance (){
time=15
while [ $time -ge 1 ] ; do

  printf "arquivos adaptados, iniciando manupulação de subvolumes em $time segundos, ctrl-c para cancelar" 
  sleep 1s
  let "time--" 
done
mount_device_to_manage_subvols
}

function mount_device_to_manage_subvols(){
  mount $rootblock -o "subvolid="5 $toplevel_dir &&\
    moment=$(date +%Y-%m-%d--%T)
    btrfs su snap -r $toplevel_dir/$subvol_to_move $toplevel_dir/@root-pre-stateless-in--$moment &&\
    mv $toplevel_dir/$subvol_to_move $toplevel_dir/$default_root &&\
    btrfs filesystem sync $toplevel_dir &&\
    copy_scripts_to_root
}
function copy_scripts_to_root(){
  cp usr/local/sbin/base-manager /usr/local/sbin/base-manager &&\
  cp usr/local/sbin/pac-base /usr/local/sbin/pac-base &&\
  cp usr/local/sbin/commit-root /usr/local/sbin/commit-root &&\
  cp usr/lib/initcpio/hooks/stateless-mode-boot /usr/lib/initcpio/hooks/stateless-mode-boot &&\
  cp usr/lib/initcpio/install/stateless-mode-boot /usr/lib/initcpio/install/stateless-mode-boot &&\
  mkdir -p /etc/pacman.d/hooks &&\
  cp etc/pacman.d/hooks/01-commit-root.hook /etc/pacman.d/hooks/01-commit-root.hook &&\
  chmod a+x /usr/local/sbin/base-manager &&\
  chmod a+x /usr/local/sbin/pac-base &&\
  chmod a+x /usr/local/sbin/commit-root &&\
  chmod a+x /usr/lib/initcpio/hooks/stateless-mode-boot &&\
  chmod a+x /usr/lib/initcpio/install/stateless-mode-boot &&\
  end_implementation
}
function edit_hooks_line_vars (){
  btrfs su cr $toplevel_dir/$default_user_data &&
  printf "
  O sistema de arquivos foi preparado, e os scripts estão nos locais e com as permissões corretas
  edite seu /etc/mkinitcpio.conf, colocando AO FINAL, como ULTIMO HOOK, stateless-mode-boot.
  edite seu /etc/pacman.conf, descomentando a linha HookDir
  Regere o init com mkinitcpio -P
  Em seguida, (se efi), monte sua partição efi em /boot/efi.
  INSTALE e ATUALIZE a grub e reinicie
"
  exit 0
}
####################################--initial-vars--################################################################
rootblock=$(grub-probe / --target=device)
rootfilesystem=$(grub-probe /)
subvol_to_move=$(grub-mkrelpath /)
toplevel_dir=$(mktemp -d -p /tmp)
default_root="@base_system"
default_user_data="@user_state"
check_filesystem
