# Stateless Arch <h1>
Inspirado em sistemas como o Clear Linux, Fedora SilverBlue e Suse MicroOS, decidi tentar trazer algo semelhante a eles para o ArchLinux. Essa ferramenta visa permitir que um rm -rf --no-preserve-root não seja catastrófico, pelo contrário, limpe todas as suas configurações, e traga o sistema para um ponto conhecido, atualizado, onde estejam somente os programas e configurações padrões do repositório. 
Se valendo de overlayfs, e de como é fácil adicionar tarefas ao init do ArchLinux, é possível montar /etc/, /var, /root, /mnt, /home, /opt, /srv, /usr/local/sbin com permissão de leitura e escrita sobre uma raiz read-only (inspirado pelo código de Antynea em https://github.com/Antynea/grub-btrfs).
É possível fazer isso sobre qualquer sistema de arquivos, porém, com btrfs, se ganha outra capacidade, como se sabe: snapshots baratos.

Com mais uma pequena dose de bash script, aliado à capacidade de configurar o pacman de executar rotinas customizadas quaisquer pré operações, ganhamos a capacidade de, via sistema de arquivos, criar commits, a cada modificação de pacotes.
A arquitetura do boot consiste então em 3 camadas:

**Primeira camada:** um subvolume btrfs, com permissão de leitura e escrita, onde está instalado o ArchLinux, com todas as pastas do root, **incluindo** /boot (obviamente /boot/efi será um ponto de montagem para fat32 EFI durante a instalação da grub). Essa raiz pode inicialmente possuir configurações mínimas, somente senha root, locales, e os arquivos e modificações necessárias para que esse init-hook funcione.O próprio fstab não precisa ficar aqui. No momento (manhã de 18 de junho de 2022), é necessário um ponto de montagem para o overlay do usuário. Talvez exista como dispensar até mesmo isso, precisa de testes.

**Segunda camada:** um overlayfs somente leitura, criado e montado pelo init sobre a raiz inteira, que visa impedir o uso direto do pacman sobre a camada de configurações do usuário. O pacman não deve ser usado diretamente pelo usuário, uma vez que isso faria o /etc do usuário reter os arquivos de configuração padrão dos programas, e /var pelos dados do pacman. Num cenário de factory-reset, a falta dos arquivos de configuração de /etc causaria problemas em diversas aplicações, sendo necessários reinstalar todas somente para obter novamente seus arquivos de configuração. E isso seria impossível pelo estado inconsistente em que o próprio pacman se encontraria devido à deleção de /var. Clear Linux modifica todos os seus pacotes para que fiquem restritos a /usr hierarquia; Suse MicroOS mantem o /etc incluso no root, e não depende de /var para o zypper a não ser para cache. Aqui ambos os conceitos são verdadeiros ao mesmo tempo; existe um /etc e um /var onde idealmente somente o pacman deve escrever, e que são versionado nos commits junto com o root, e um segundo /etc e /var montado por cima dele, onde o usuário pode escrever livremente, como pode ver a seguir.

**Terceira camada:** um subvolume btrfs com permissão de leitura e escrita, montado como overlay pelo init, contendo /etc/, /var, /root, /mnt, /home, /opt, /srv e /usr/local/sbin, acima da camada somente leitura anterior. Assim, configurações de serviços, montagem, udev e afins podem ser honradas apropriadamente pelo systemd, na fase 2 da inicialização. Esse subvolume tem o nome explicitamente declarado no init; renomear o subvolume sem mudá-lo em /usr/lib/initcpio/hooks/stateless-mode-boot e reconstruir o init implica em um boot quebrado, mesmo usando o initrd fallback

**ATENÇÃO: esse hook deve ser o último em HOOKS no /etc/mkinitcpio.conf, é compatível com os hooks ativos por padrão no ArchLinux, e NÃO é compatível os hooks grub-btrfs-overlayfs e systemd; a combinação com outros hooks não foi testada**

Quaisquer pontos de montagem declarados /etc/fstab overlay serão honrados normalmente

Antes que você se pergunte, porque não configurar o subvolume root diretamente como readonly, como o Suse MicroOS, eu explico: Se isso fosse feito, se perderia a capacidade de live-patch. Seria necessário reiniciar a cada instalação/remoção de pacotes, o que é um grande incoveniente. Da forma como foi projetado aqui, é possível, e fácil, atualizar, e manusear pacotes de forma que ela permaneça sempre nos padrões do repositório ou muito perto disso, como se tivesse acabado de fazer um pacstrap. E usando btrfs, e um simples hook no pacman, é possível gerar commits bootáveis a cada atualização.

Assim como no Suse MicroOS, e em qualquer sistema desse tipo, o sistema não é à prova de um usuário com nível de acesso root que QUEIRA quebrar o sistema. Um exemplo simples : troque o nome do subvolume root no Suse MicroOS, e reinicie, e o boot parará no init. Apague a configuração de boot do Clear Linux, e algo parecido ocorrerá. Apague grub.cfg do Fedora Silverblue, e se depare com grub-shell. Em qualquer que seja o sistema, um dd de dev/zero sobre o root o destrói, obviamente. Portanto, não se trata de desafiar o usuário a conseguir quebrar uma instalação, e sim de dificultar ao máximo que um usuário que quer MANTER uma instalação funcional a perca.

Habilitar stateless-arch **será** simples como:

* pacstrap em um subvolume btrfs. Deve incluir arch-install-scripts grub grub-btrfs bash. Dracut não suportado.
* arch-chroot
* montar fat-32 em /boot/efi, se efi
* passwd
* pacman -S git
* git clone desse repositório
* executar o scritp enable-stateless-arch.sh, respondendo suas perguntas e seguindo suas instruções
* remover /etc/fstab (sim, exatamente)
* reboot



Para usar um ArchLinux com stateless-arch, o usuário deve aceitar e conviver com algumas limitações e mudanças de usabilidade:

* atualização e remoção de pacotes somente de forma mediada por pac-base, não diretamento pelo pacman.

* atualização do grub.cfg somente de forma mediada por base-manager --bootloader-update, e não diretamente pelo grub-mkconfig

* caso o usuário regrida para um commit onde não exista um determinado binário, mas em seu /etc overlay exista uma configuração de serviço que aponte para esse binário, é possível que o boot seja parado. Isso não implica em um commit quebrado, somente em uma configuração de serviço que não pode ser honrada. Esse gerenciamento é totalmente delegado ao usuário. Ao regredir commits, cuide para que nesse commit estejam todos os binários para os quais seus serviços apontam, ou apague esses serviços.

* como já deu para perceber, grub como bootloader é uma exigencia aqui. Faço isso para poder incluir o próprio kernel nos commits. Dado que a grub consegue lidar com kernel e initrd sob btrfs, comprimido ou não, seja em legacy ou em efi, se torna uma ferramenta com um fator social e até mesmo ambiental importante : hardware sem capacidade de boot efi continua sendo suportado, e ao ter toda a raiz inclusa em commits, a recuperação de uma atualização problemática, ou mesmo um reset total não passa por mais carga de acesso aos repositórios para baixar iso e pacotes. Mesmo implementar o ArchLinux em outra máquina se torna fácil como um btrfs send via rede de seu último commit, com a certeza que isso não incluirá chaves ssh,configurações de usuários e grupos, pontos de acesso wifi, ou outras configurações sensíveis.

* a geração de locale-gen deve ser incluída diretamente na raiz, o que pode ser incoveniente caso o usuário troque constantemente de idioma; editar a raiz diretamente será discutido a seguir. Uma alternativa pode ser, durante a instalação, antes de instalar e habilitar stateless-arch, descomentar todos os locales em /etc/locale.gen, e assim gerar todos.

Ainda que seja possível e facilitado a edição da raiz online, de forma que um reset mantenha todos os seus programas e apague somente configurações, aconselho FORTEMENTE que evite fazer isso, a menos que não possa evitar. Delegue o máximo de programas possível á flatpak, appimage e snap, ou, minha alternativa preferida, o excelente https://github.com/89luca89/distrobox de 89luca89. Dado que tanto /var quando a home do usuario são separados, voltar commits da raiz não implica em perder acesso a nenhum desses programas. Delegue á base somente o suficiente para subir o modo gráfico, drivers em geral, suporte a hardware, virtualizadores, o suporte a containers,e outras ferrramentas que dependam de alto nivel de acesso, como por exemplo particionadores de disco. Uma limitação conhecida é não poder usar o WayDroid de dentro de um container, por ele realizar montagens, que não são possíveis de dentro de um container. Mesmo programas de edição de som são plenamente usáveis de dentro de um container (testado usando pipewire e wireplumber). Caso precise realmente editar a raiz, base-manager --provide-rw-root proverá um ambiente chroot onde o subvolume da primeira camada será plenamente acessivel. O próprio DistroBox pode ser instalado na home do usuário, ainda que o podman não.

Atualizações e manuseio de programas é fácil como um pac-base [cli normal do pacman]. Pac-base será um bash scritp simples, que montará o subvolume root diretamente, por cima dele montará um subvolume em /var/cache/pacman/pkg, e fará um bind de /etc/pacman.d, /etc/pacman.conf, /etc/default/grub, /etc/grub.d, e em seguida, provido por arch-install-scripts, executará arch-chroot pacman [export dos comandos passados para o pac-base]. Em /etc/pacman.d/hooks havera um hook pre operação, que apontara para outro bash script, chamado commit-root. Como diz o nome, esse script será responsável por gerar um commit do root via snapshot btrfs antes da operação, e atualizar o grub.cfg. O excelente grub-btrfs de Antynea se encarregará de popular o menu de boot com os commits. Commit-root pode ser trocado por qualquer alternativa que funcione em ambiente chroot. Snapper + snap-pac e  Timershift + timeshift-autosnap não foram testados. A montagem explicita de /var/cache/pacman/pkg é para que os commits todos não acabem levando junto a cache do pacman. O uso de um tmpfs foi considerado, mas rejeitado por causar perda dos pacotes já baixados em caso de desligamento repentino, ou pelo óbvio alto uso de RAM em operações densas, como um grande update ou instalação de múltiplos pacotes. O nome desse subvolume é declarado explicitamente no script, e ele será criado durante a instalação dessa ferramenta.Obviamente o usuário pode alterar esse comportamento conforme desejar.

Caso use commit-root, será papel do usuário implementar quaisquer políticas que queira de garbage collector dos commits. No meu uso pessoal, um temporizador systemd roda um script bash a cada 15 dias, e deixa os 20 commits mais recentes. Snapper e Timeshift (que repito, NÃO foram testados) possuem cada um suas próprias formas de configurar isso.
Base-manager --restore-root só deve ser usado se seus commits forem gerados por commit-root; se usou outra ferramenta, confie nela também para a restauração.

Os scripts base-manager,pac-base e commit-root serão salvos em /usr/local/sbin, de forma que uma edição do usuário em seu próprio overlay valerá para alterar quaisquer parâmetros que queira. Isso NÃO é verdadeiro para o hook do init.

O sistema dessa forma será altamente resiliente. De fato, excetuando algo que afete diretamente o sistema de arquivos, ou apagar as imagens da grub (mbr do disco se disco mbr+legacy, partição biosboot se gpt+legacy, arquivos da partição fat-32 se efi), o sistema é facilmente recuperável em praticamente qualquer situação sem necessidade de live-boot. Novo kernel/driver de vídeo problemático? Use um commit anterior. A grub não encontrou o arquivo de configuração e caiu no shell? Use a cli para chamar o configfile de qualquer um dos commits, todos eles terão um grub.cfg. Grub-rescue? Chame o binário da grub de qualquer um dos commits, e você terá o grub-shell completo, se onde será possível chamar o grub.cfg de qualquer um dos commits.

O uso do hook init da forma em que está nesse momento (18 de junho de 2022) já é possível; porem exige um usuário com mínimo conhecimento de shell scritp para le-los, entender o que fazem, e tornar seu sistema de arquivos compatível; base-manager não está completo, portanto não é uma ferramenta usável. Suas funções devem ser desempenhadas manualmente, ou, se você entendeu as abstrações envolvidas e descritas aqui, e conhece bash script, fique a vontade para contribuir. Mesmo quando toda essa ferramenta for terminada, **NÃO SERÁ** indicada para usuários inexperientes. Problemas que exijam conhecimento de pontos de montagem, manipulação do processo de boot e de subvolumes btrfs podem surgir

 **MANTENHA /boot/efi DESMONTADO.**

**Podem haver problemas e incompatibilidades que eu não encontrei nos meus testes, e que podem aparecer somente com o uso de determinados programas, ou combinação de programas.**

**A máquina é sua, o sistema de arquivos é seu, a decisão de usar esses scripts foi sua, portanto os riscos e prejuízos são seus.**

**O suporte a luks e a secure-boot não foi testado.**
