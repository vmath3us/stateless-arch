# Stateless Arch <h1>

Inspirado em sistemas como o Clear Linux, Fedora SilverBlue e Suse MicroOS, decidi tentar trazer algo semelhante a eles para o ArchLinux. Essa ferramenta visa permitir que um rm -rf --no-preserve-root não seja catastrófico, pelo contrário, limpe todas as suas configurações, e traga o sistema para um ponto conhecido, atualizado, onde estejam somente os programas e configurações padrões do repositório. 
Se valendo de overlayfs, e de como é fácil adicionar tarefas ao init do ArchLinux, é possível montar /etc/, /var, /root, /mnt, /home, /opt, /srv, /usr/local e /usr/lib/systemd com permissão de leitura e escrita sobre uma raiz read-only (inspirado pelo código de Antynea em https://github.com/Antynea/grub-btrfs).
É possível fazer isso sobre qualquer sistema de arquivos, porém, com btrfs, se ganha outra capacidade, como se sabe: snapshots baratos.

Com mais uma pequena dose de bash script, aliado à capacidade de configurar o pacman de executar rotinas customizadas quaisquer pré operações, ganhamos a capacidade de, via sistema de arquivos, criar commits, a cada modificação de pacotes.

Para que funcione conforme projetado, o initrd é customizado, de forma que a arquitetura do root usado normalmente consiste então em 3 camadas:

**Primeira camada:** um subvolume btrfs, com permissão de leitura e escrita, onde está instalado o ArchLinux, com todas as pastas do root, **incluindo** /boot (obviamente /boot/efi será um ponto de montagem para fat32 EFI durante a instalação da grub, se efi). Essa raiz pode inicialmente possuir configurações mínimas, somente senha root, locales, e os arquivos e modificações necessárias para que esse init-hook funcione.O próprio fstab não precisa ficar aqui, sua edição durante a instalação do sistema pode ser ignorada.

**Segunda camada:** um overlayfs somente leitura, criado e montado pelo init sobre a raiz inteira, que visa impedir o uso direto do pacman sobre a camada de configurações do usuário. O pacman não deve ser usado diretamente pelo usuário, uma vez que isso faria o /etc do usuário reter os arquivos de configuração padrão dos programas, e /var do usuário reter os banco de dados do pacman. Num cenário de factory-reset, a falta dos arquivos de configuração de /etc causaria problemas em diversas aplicações, sendo necessários reinstalar todas somente para obter novamente seus arquivos de configuração. E isso seria potencialmente impossível pelo estado inconsistente em que o próprio pacman se encontraria devido à deleção de arquivos em /var. Clear Linux modifica todos os seus pacotes para que fiquem restritos a /usr hierarquia; Suse MicroOS mantem o /etc incluso no root, e não depende de /var para o zypper a não ser para cache. Aqui ambos os conceitos são verdadeiros ao mesmo tempo; existe um /etc e um /var onde idealmente somente o pacman deve escrever, e que são versionado nos commits junto com o root, e um segundo /etc e /var montado por cima dele, onde o usuário pode escrever livremente, como visto a seguir.

**Terceira camada:** um subvolume btrfs com permissão de leitura e escrita, que conterá diretórios para permitir montagem overlay com permissão de escrita em /etc/, /var, /root, /mnt, /home, /opt, /srv, /usr/local/ e /usr/lib/systemd, acima da camada somente leitura anterior. Assim, configurações de serviços, montagem, udev e afins podem ser honradas apropriadamente pelo systemd, na fase 2 da inicialização, e scripts customizados relacionados á suspensão e desligamento podem ser criados livremete (IMPORTANTE= alterar atributos dos binários sobre o overlay, após o sistema devidamente iniciado, ainda que não afete os arquivos reais, pode causar problemas na inicialização seguinte; esse overlay em específico (/usr/lib/systemd/) deve ser usado somente nos casos acima mencionados, adicionar scripts e serviços associados a suspensão e desligamento do sistema.) O subvolume que abriga os overlays tem o nome explicitamente declarado no init; renomear o subvolume sem mudá-lo em /usr/lib/initcpio/hooks/stateless-mode-boot e reconstruir o init implica em um boot quebrado. Será tratado abaixo sobre modo de manutenção para essa situação.

**ATENÇÃO: esse hook deve ser o último em HOOKS no /etc/mkinitcpio.conf, é compatível com os hooks ativos por padrão no ArchLinux, e NÃO é compatível com os hooks grub-btrfs-overlayfs e systemd; a combinação com outros hooks não foi testada**

**Sobre pontos de montagem e serviços**

Quaisquer pontos de montagem declarados /etc/fstab do overlay, bem como serviços de /etc/systemd/system serão honrados normalmente a princípio, mas quando se trata de subvolumes do mesmo dispositivo de bloco, há uma limitação: como a raiz do sistema é um subvolume com permissão de escrita, e não é desmontada e remontada pelo systemd para honrar uma entrada no fstab (que sequer precisa existir), todos os demais subvolumes do mesmo dispositivo de bloco seguem essa mesma montagem, ou seja, sem compressão, ainda que declarada corretamente no fstab. Uma operação de remount corrige isso, portando acrescentei nessa ferramenta um serviço do systemd que fará tal operação no início do sistema. 
** A home DEVE ser uma montagem verdadeira, e não somente o overlay. Ferramentas de gerenciamento de container (docker/podman) não funcionam corretamente quando seu armazenamento é um overlay. Crie um subvolume/partição para a home, e o coloque corretamente no fstab. O mesmo pode ser verdade (não testado) para bancos de dados e imagens de máquinas virtuais em /var. Se usa algumas dessas coisas no dia a dia, e precisa que fiquem em /var, tenha partições e subvolumes verdadeiros para montar apropriadamente. Se possuir montagens ANINHADAS na home,remova a linha referente à montagem dela no scritp do hook, e regere o init (não se esqueça de remover o && antes dessa linha).



**Live-patch**

Ainda que não plenamente funcional, é possível atualizar o sistema e instalar/desinstalar pacotes sem reinício. E usando btrfs, e um simples hook no pacman, é possível gerar commits bootáveis antes de cada operação. O suporte a live-patch porém é experimental, portanto espere inconsistências do tipo:
1. Remover um pacote não o remove do path, nem remove seu ícone da área de trabalho imediatamente. As vezes é possível até mesmo seguir executando, caso seja um programa simples sem dependências, mas não confie no pleno funcionamento, espere por inconsistências, não arrisque por exemplo dados sensível em um programa nesse estado.  Um reinício corrige essa situação
2. Instalar um pacote não cria seu respectivo ícone na área de trabalho imediatamente. As vezes é possível executá-lo via terminal, e caso seja um program gráfico, sua janela se abrirá, mas não confie no pleno funcionamento, espere por inconsistências, não arrisque por exemplo dados sensível em um programa nesse estado. Um reinício corrige tudo isso, gerando o ícone e todo o resto.
3. Os dois pontos acima são verdadeiros para atualização do sistema.

**Ou seja, ainda que não totalmente necessário, leve como regra que,manuseou pacotes da base, reinicie. Não haverá telas de loading como em outros sistema por aí, a operação já ocorreu, só seu estado precisa ser fixado**

A ideia é que o sistema permaneça sempre em "estado de pacstrap": Qualquer commit da base terá somente pacotes do pacman, em seus padrões, somado à pouca configuração (senha root e locales) de /etc; faça todo o resto em seu overlay, e na sua home, e você poderá enviar seu root para outra pessoa/dispositivo ( usando btrfs send/receive, tar, rsycn, ou que for), com a certeza de não enviar junto chaves ssh, senhas de wifi, ou outras informações sensíveis.

Assim como no Suse MicroOS, e em qualquer sistema desse tipo, o sistema não é à prova de um usuário com nível de acesso root que QUEIRA quebrar o sistema. Um exemplo simples : troque o nome do subvolume root no Suse MicroOS, e reinicie, e o boot parará no init. Apague a configuração de boot do Clear Linux, e algo parecido ocorrerá. Apague grub.cfg do Fedora Silverblue, e se depare com grub-shell. Em qualquer que seja o sistema, um dd de dev/zero sobre o root o destrói, obviamente. Portanto, não se trata de desafiar o usuário a conseguir quebrar uma instalação, e sim de dificultar ao máximo que um usuário que quer MANTER uma instalação funcional a perca.

Habilitar stateless-arch é simples como:

* pacstrap em um subvolume btrfs. Deve incluir arch-install-scripts grub grub-btrfs bash. Dracut não suportado.
* arch-chroot
* passwd
* gerar locales
* pacman -S git
* git clone desse repositório
* executar o scritp install-stateless-arch-tools.sh
* seguir as instruções finais do scritp (somente operações normais em qualquer instalação do ArchLinux)
* reiniciar

Para usar um ArchLinux com stateless-arch, o usuário deve aceitar e conviver com algumas limitações e mudanças de usabilidade:

* atualização e remoção de pacotes somente de forma mediada por pac-base, não diretamento pelo pacman.

* atualização do grub.cfg somente de forma mediada por base-manager --bootloader-update, e não diretamente pelo grub-mkconfig

* caso o usuário regrida para um commit onde não exista um determinado binário, mas em seu /etc overlay exista uma configuração de serviço que aponte para esse binário, é possível que o boot seja parado. Isso não implica em um commit quebrado, somente em uma configuração de serviço que não pode ser honrada. Esse gerenciamento é totalmente delegado ao usuário. Em alguns casos, o shell de emergência do boot pode bastar para remover a inconsistência encontrada e permitir que o boot prossiga. De toda forma, ao regredir commits, cuide para que no commit de destino estejam todos os binários para os quais seus serviços apontam, ou apague esses serviços de seu overlay. Passar "disablehooks=stateless-mode-boot" na linha de comando do kernel iniciará o sistema diretamente na primeira camada, com plenas permissões. O usuário deve então montar seu overlay manualmente, e inspecionar seus serviços, montagens e configurações em busca do problema que porventura impediram o sucesso do boot.Essa opção deve ser usada APÓS tentativas malsucedidas de boot em commits do root. Caso seja impossível estabelecer qual a causa verdadeira do problema rapidamente, o usuário pode simplesmente usar base-manager --reset-user-data, que irá mover o overlay de dados do usuário para um commit, e gerar um novo; O hook no init se encarregará de criar as pastas necessárias, e o sistema iniciara no estado da base, ou do commit escolhido, pronto para novas modificações. O overlay de usuário anterior poderá então ser depurado com calma, ou deletado caso o usuário estabeleça que não consegue/não vale a pena eliminar todos os problemas encontrados. Essa deve ser uma situação raríssima, mas possível, portanto deve constar nessa documentação.

* como já deu para perceber, grub como bootloader é uma exigencia aqui. Faço isso para poder incluir o próprio kernel nos commits. Dado que a grub consegue lidar com kernel e initrd sob btrfs, comprimido ou não, seja em legacy ou em efi, se torna uma ferramenta com um fator social e até mesmo ambiental importante : hardware sem capacidade de boot efi continua sendo suportado, e ao ter toda a raiz inclusa em commits, a recuperação de uma atualização problemática, ou mesmo um reset total não passa por mais carga de acesso aos repositórios para baixar iso e pacotes. Mesmo implementar o ArchLinux em outra máquina se torna fácil como um btrfs send via rede de seu último commit, com a certeza que isso não incluirá chaves ssh,configurações de usuários e grupos, pontos de acesso wifi, ou outras configurações sensíveis. O sistema está sempre em "estado de pacstrap", ou muito perto disso.

* a geração de locale-gen deve ser incluída diretamente na raiz, o que pode ser incoveniente caso o usuário troque constantemente de idioma; editar a raiz diretamente será discutido a seguir. Uma alternativa pode ser, durante a instalação, antes de instalar e habilitar stateless-arch, descomentar todos os locales em /etc/locale.gen, e assim gerar todos.

* Devido o estado experimental do live-patch, se valer primariamente de flatpak, appimage, ou, minha alternativa preferida, o excelente Distrobox de 89luca89. Dado que tanto /var quando a home do usuario são separados (ver considerações na sessão sobre montagens), voltar commits da raiz não implica em perder acesso a nenhum desses programas. Delegue á base somente o suficiente para subir o modo gráfico, drivers em geral, suporte a hardware, virtualizadores, o suporte a containers,e outras ferrramentas que dependam de alto nivel de acesso, como por exemplo particionadores de disco.  Mesmo programas de edição de som são plenamente usáveis de dentro de um container (testado usando pipewire e wireplumber). O próprio DistroBox pode ser instalado na home do usuário. Os ícones de desktop de flatpaks, appimages e exportados via Distrobox surgem normalmente em sua área de trabalho, o funcionamento é totalmente transparente. E com distrobox é possível usar pacotes de outras distribuições, não somente do ArchLinux (eu tenho a leve impressão que a maior parte dos usuários de Stateless-Arch usará Alpine como base de seus containers sempre que possível).

Atualizações e manuseio de programas **(leve em conta a sessão live-patch**) são possíveis usando pac-base, seguido da cli normal do pacman. Pac-base é somente um bash scritp simples, que montará o subvolume root diretamente, por cima dele uma montagem bind de /var/cache/pacman/pkg, /etc/mkinitcpio.conf, /etc/pacman.d, /etc/pacman.conf, /etc/default/grub, /etc/grub.d, /usr/local, e em seguida, provido por arch-install-scripts, executará arch-chroot pacman exportando os comandos passados para pac-base. Em /etc/pacman.d/hooks havera um hook pre operação, que apontara para outro bash script, chamado commit-root. Como diz o nome, esse script será responsável por gerar um commit do root via snapshot btrfs antes da operação, e atualizar o grub.cfg. O excelente grub-btrfs de Antynea se encarregará de popular o menu de boot com os commits. Commit-root pode ser trocado por qualquer alternativa que funcione em ambiente chroot. Snapper + snap-pac e  Timershift + timeshift-autosnap não foram testados. Todos os scripts foram escritos com foco em facilitar a leitura e a edição, qualquer comportamento pode ser alterado facilmente.

Caso use commit-root, será papel do usuário implementar quaisquer políticas que queira de garbage collector dos commits. No meu uso pessoal, um temporizador systemd roda um script bash a cada 15 dias, e deixa os 20 commits mais recentes. Snapper e Timeshift (que repito, NÃO foram testados) possuem cada um suas próprias formas de configurar isso. O scritp está no repositório, mas não está incluso na instalação. Copie-o manualmente caso queira usar.

Base-manager --restore-root só deve ser usado se seus commits forem gerados por commit-root; se usou outra ferramenta, confie nela também para a restauração.

Os scripts base-manager,pac-base e commit-root serão salvos em /usr/local/sbin, de forma que uma edição do usuário em seu próprio overlay valerá para alterar quaisquer parâmetros que queira. Isso NÃO é verdadeiro para o hook do init.

O sistema dessa forma será altamente resiliente. De fato, excetuando algo que afete diretamente o sistema de arquivos, ou apagar as imagens da grub (mbr do disco se disco mbr+legacy, partição biosboot se gpt+legacy, arquivos da partição fat-32 se efi), o sistema é facilmente recuperável em praticamente qualquer situação sem necessidade de live-boot. Novo kernel/driver de vídeo problemático? Use um commit anterior. A grub não encontrou o arquivo de configuração e caiu no shell? Use a cli para chamar o configfile de qualquer um dos commits, todos eles terão um grub.cfg. Grub-rescue? Chame o binário da grub de qualquer um dos commits, e você terá o grub-shell completo, se onde será possível chamar o grub.cfg de qualquer um dos commits.

Para editar diretamente a base, use base-manager --provide-rw-root. A base será montada, e plenamente acessível e manuseável conforme o usuário desejar. Um commit será gerado antes, portanto aguarde a atualização do bootloader.

O uso do hook init da forma em que está nesse momento já é possível, mas se trata de uma ferramenta beta. Mesmo quando for terminada, **NÃO SERÁ** indicada para usuários inexperientes. Problemas que exijam conhecimento de pontos de montagem, manipulação do processo de boot e de subvolumes btrfs podem surgir.

 **NÃO INCLUA A PARTIÇÃO EFI NO SEU FSTAB.**

**Podem haver problemas e incompatibilidades que eu não encontrei nos meus testes, e que podem aparecer somente com o uso de determinados programas, ou combinação de programas, ou cenários especiais.**

**A máquina é sua, o sistema de arquivos é seu, a decisão de usar esses scripts foi sua, portanto os riscos e prejuízos são seus.**

**O suporte a luks e a secure-boot não foi testado.**
