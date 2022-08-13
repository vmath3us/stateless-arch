#!/bin/bash
####################################--initial-vars--################################################################
rootblock=$(grub-probe / --target=device)
rootfilesystem=$(grub-probe /)
subvol_to_move=$(grub-mkrelpath /)
toplevel_dir=$(mktemp -d -p /tmp)
#####################--change-here-and-in-all-files-usr/local/sbin--##########################
default_root="@base_system"
#####################--change-here-and-in-usr/lib/inictpio/hooks/stateless-mode-boot--##########################
default_sysadmin_data="@sysadmin_state"
#############################################################################################################
function welcome (){
  printf "
  ###############################################################################################
  ###############################################################################################
                                  Stateless-Arch
  ###############################################################################################
  ###############################################################################################

"
check_user
}
function check_user (){
  user=$(whoami)
  if [ "$user" != "root" ] ; then
    printf "
    execute como root. Saindo com status de erro

" &&\
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
          printf "
          use somente em um root inteiramente btrfs, dentro de um subvolume. Saindo com status de erro
"
          exit 1
        else
          printf "
          sistema de arquivos conferido, testando dependencias
" &&\
          check_deps
        fi
    else
      printf "
      use a raiz inteira, em um único subvolume btrfs. /boot separado incompatível. Saindo com status de erro"
      exit 1
    fi
}
function check_deps (){
  if [ -f /etc/grub.d/41_snapshots-btrfs ] && command -v grub-install && command -v arch-chroot ; then
    printf "
    dependencias conferidas, adaptando arquivos
" &&\
        last_chance
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
function last_chance (){
time=15
sleep 1s
while [ $time -ge 1 ] ; do
  printf "

  ###############################################################################################
  ###############################################################################################
                                  Stateless-Arch
  ###############################################################################################
  ###############################################################################################

"
  echo "iniciando manipulação de subvolumes e propagação de arquivos em $time segundos, ctrl-c para cancelar" 
  sleep 1s
  let "time--" 
done
mount_device_and_manage_subvols
}

function mount_device_and_manage_subvols(){
  mount $rootblock -o "subvolid="5 $toplevel_dir &&\
    moment=$(date +%Y-%m-%d--%H-%M-%S)
    btrfs su snap $toplevel_dir/$subvol_to_move $toplevel_dir/@root-pre-stateless-in--$moment &&\
    mv $toplevel_dir/$subvol_to_move $toplevel_dir/$default_root &&\
    btrfs filesystem sync $toplevel_dir &&\
    btrfs su snap -r $toplevel_dir/$default_root $toplevel_dir/@root-pos-stateless-in-$moment &&\
      if [ $? -eq 0 ] ; then
        btrfs filesystem sync $toplevel_dir &&\
          copy_scripts_to_root
    else
      printf "
        um erro na manipulação dos subvolumes ocorreu, saindo com status de erro.
        Verique suas alterações no cabeçalho do scritp de instalação, ou por colisão entre
      os nomes aqui usados e seus subvolumes já existentes
"     &&\
      exit 1
   fi
}
function copy_scripts_to_root(){
  cp usr/local/sbin/base-manager /usr/local/sbin/base-manager &&\
  cp usr/local/sbin/remountfs /usr/local/sbin/remountfs &&\
  cp usr/local/sbin/pac-base /usr/local/sbin/pac-base &&\
  cp usr/local/sbin/garbageauto /usr/local/sbin/garbageauto &&\
  cp usr/lib/initcpio/hooks/stateless-mode-boot /usr/lib/initcpio/hooks/stateless-mode-boot &&\
  cp usr/lib/initcpio/install/stateless-mode-boot /usr/lib/initcpio/install/stateless-mode-boot &&\
  mkdir -p /etc/systemd/system &&\
  cp etc/systemd/system/remount.service /etc/systemd/system/remount.service &&\
  cp -r etc/systemd/system/multi-user.target.wants /etc/systemd/system/multi-user.target.wants &&\
  chmod a+x /usr/local/sbin/base-manager &&\
  chmod a+x /usr/local/sbin/pac-base &&\
  chmod a+x /usr/local/sbin/remountfs &&\
  chmod a+x /usr/lib/initcpio/hooks/stateless-mode-boot &&\
  chmod a+x /usr/lib/initcpio/install/stateless-mode-boot &&\
  end_implementation || printf "
    os scripts de implementação não estão nos locais corretos. Clone o repositório novamente,
    ou edite o script de instalação para refletir corretamente suas mudanças. Saindo com status de erro
"

}
function end_implementation (){
  moment=$(date +%Y-%m-%d--%H-%M-%S) &&\
  btrfs su cr $toplevel_dir/$default_sysadmin_data &&
      err=$?
    if [ $err -eq 0 ] ; then
            btrfs filesystem sync $toplevel_dir &&\
            umount -Rv $toplevel_dir &&\
            printf "
            O sistema de arquivos foi preparado, e os scripts estão nos locais e com as permissões corretas
            edite /etc/mkinitcpio.conf, colocando AO FINAL, como ULTIMO HOOK, stateless-mode-boot. (ler README para incompatibilidades)
            Regere o init com mkinitcpio -P
            Em seguida, (se efi), monte sua partição efi em /boot/efi,
            INSTALE e ATUALIZE a grub e reinicie.
            Para iniciar sem stateless-mode-boot, aperte c no menu de boot,
            adicione, ao final da linha do kernel
            disablehooks=stateless-boot-mode, e aperte F10
          
            Se assegure de ter lido E COMPREENDIDO completamente o README

            Bem vindo ao Stateles Arch
          
" &&
            exit $err

    else
            printf "
              um erro na manipulação dos subvolumes ocorreu, saindo com status de erro.
              Verique suas alterações no cabeçalho do scritp de instalação, ou por colisão entre
            os nomes aqui usados e seus subvolumes já existentes
" &&
            exit $err
    fi
}
welcome
