# Stateless Arch <h1>


**Esse é um projeto de atualizações contínuas. Se assegure de ter uma cópia recente do repositório antes de testar. As releases são únicamente para marcar a evolução do código, e não devem ser usadas**

Inspirado em sistemas como o Clear Linux, Fedora SilverBlue e Suse MicroOS, decidi tentar trazer algo semelhante a eles para o ArchLinux. Essa ferramenta visa permitir que o root controlado pelo pacman seja diferente do root do sysadmin. Dessa forma, é possível descartar configurações problemáticas sem perder atualizações, e também é possível reverter atualizações sem descartar nenhuma das configurações do sysadmin.

Se valendo de overlayfs, e de como é fácil adicionar tarefas ao init do ArchLinux, um script embutido no initrd se encarregará de montar /etc/, /var, /root, /mnt, /home, /opt, /srv, /usr/local e /usr/lib/systemd com permissão de leitura e escrita sobre uma raiz read-only (inspirado pelo código de Antynea em https://github.com/Antynea/grub-btrfs).

É possível fazer isso sobre qualquer sistema de arquivos, porém, com btrfs, se ganha outra capacidade, como se sabe: snapshots baratos.

Com mais uma pequena dose de bash script, aliado à capacidade de configurar o pacman de executar rotinas customizadas quaisquer pré operações, ganhamos a capacidade de, via sistema de arquivos, criar commits, a cada modificação de pacotes.

# Arquitetura <h2>
Ao concluir o boot, a raiz consistirá em três camadas, sendo:

**Primeira camada: PacmanRoot**: um subvolume btrfs, com permissão de leitura e escrita, onde está instalado o ArchLinux, com todas as pastas do root, **incluindo** /boot (obviamente /boot/efi será um ponto de montagem para fat32 EFI durante a instalação da grub, se efi). Esse root pode inicialmente possuir configurações mínimas, somente senha root, locales, e os arquivos e modificações necessárias para que Stateless Arch funcione.O próprio fstab não precisa ficar aqui, sua edição durante a instalação do sistema pode ser ignorada. Esse subvolume é mantido com permissão de leitura e escrita, para que não sejam necessárias duas operações de commit (como no Suse MicroOS), durante o uso (mediado) do pacman. O uso direto do pacman (ou de qualquer ferramenta que seja, como por exemplo um rm -rf) para modificar PacmanRoot é impedido pela segunda camada. Alterar PacmanRoot deve ser evitado, e se necessário, o processo é mediado, como pode ser visto mais adiante.

**Segunda camada: Proteção**: um overlayfs tmpfs somente leitura, criado e montado pelo init sobre a raiz inteira, que visa impedir o uso direto do pacman sobre a camada de configurações do sysadmin. O pacman não deve ser usado diretamente pelo sysadmin, uma vez que isso faria seu /etc reter os arquivos de configuração padrão de alguns programas, e /var do sysadmin reter os banco de dados do pacman. Num cenário de --reset-sysadmin-data (discutido a seguir), a falta dos arquivos de configuração de /etc causaria problemas em diversas aplicações, sendo necessários reinstalar todas somente para obter novamente seus arquivos de configuração. E isso seria potencialmente impossível pelo estado inconsistente em que o próprio pacman se encontraria devido à deleção de arquivos em /var. Clear Linux modifica todos os seus pacotes para que fiquem restritos a /usr, e seus arquivos sejam simplesmente copiados para /etc caso não existam; Suse MicroOS mantem o /etc incluso nos commits do root, e não depende de /var para o zypper a não ser para cache. Aqui ambos os conceitos são "verdadeiros" ao mesmo tempo; existe um /etc e um /var onde idealmente somente o pacman deve escrever, e que são versionados nos commits junto com o root do pacman, e um segundo /etc e /var montado por cima dele, onde o sysadmin pode escrever livremente, como visto a seguir.

**Terceira camada:Sysadmin** um subvolume btrfs com permissão de leitura e escrita, que conterá diretórios para permitir montagem overlay com permissão de escrita em /etc/, /var, /root, /mnt, /home, /opt, /srv, /usr/local/ e /usr/lib/systemd, acima da camada somente leitura anterior. Assim, configurações de serviços, montagem, udev e afins podem ser honradas apropriadamente pelo systemd, na fase 2 da inicialização, e scripts customizados relacionados á suspensão e desligamento podem ser criados livremete (IMPORTANTE= alterar atributos dos binários sobre o overlay, após o sistema devidamente iniciado, ainda que não afete os arquivos reais, pode causar problemas na inicialização seguinte; esse overlay em específico (/usr/lib/systemd/) deve ser usado somente nos casos acima mencionados, adicionar scripts e serviços associados a suspensão e desligamento do sistema.). O subvolume que abriga os overlays tem o nome e o tipo de compressão explicitamente declarados no init; renomear o subvolume sem mudá-lo em /usr/lib/initcpio/hooks/stateless-mode-boot e reconstruir o init implica em um boot quebrado. Será tratado abaixo sobre modo de manutenção para essa situação. Esse subvolume retem o estado do sistema, pode ser simplesmente descartado (ou renomeado), um novo ser criado, e no boot seguinte o scritp no initrd se encarregará de criar os diretórios necessários para essa camada. O sistema iniciará então no último update implementado em PacmanRoot, mas sem as configurações do sysadmin. Um usuário com experiência mínima em btrfs pode fazer essa operação manualmente de forma trivial, mas isso não é necessário: base-manager --reset-sysadmin-data intermedia essa operação de forma simples.

**ATENÇÃO: conforme explicado no script de implementação, o hook que torna isso possível deve ser o último em HOOKS no /etc/mkinitcpio.conf, é compatível com os hooks ativos por padrão no ArchLinux, e NÃO é compatível com os hooks grub-btrfs-overlayfs e systemd; a combinação com outros hooks não foi testada**

# Sobre pontos de montagem e serviços <h3>

Quaisquer pontos de montagem declarados no /etc/fstab do overlay, bem como serviços de /etc/systemd/system serão honrados normalmente a princípio, mas quando se trata de subvolumes do mesmo dispositivo de bloco, há uma limitação: como a raiz do sistema é um subvolume com permissão de escrita, e não é desmontada e remontada pelo systemd para honrar uma entrada no fstab (que sequer precisa existir), todos os demais subvolumes do mesmo dispositivo de bloco seguem essa mesma montagem, ou seja, sem compressão, ainda que declarada corretamente no fstab. Uma operação de remount corrige isso, portanto acrescentei nessa ferramenta um serviço do systemd que fará tal operação no início do sistema. **O serviço precisa ser ativado.**

**É uma boa prática existir uma montagem verdadeira para /home no fstab do sysadmin**, que será montada sobre o overlay. Ferramentas de gerenciamento de container (docker/podman) não funcionam corretamente quando seu armazenamento é um overlay. Crie um subvolume/partição para a home, e o coloque corretamente no fstab. O mesmo pode ser verdade (não testado) para bancos de dados e imagens de máquinas virtuais em /var. Se usa algumas dessas coisas no dia a dia, e precisa que fiquem em /var, tenha partições e subvolumes verdadeiros para montar apropriadamente. Se possuir montagens ANINHADAS(por ex, /home é um subvolume/partição, e /home/$USER/Documentos é outro),remova a última linha, referente ao overlay da home no scritp do hook, e regere o init. Enfim, teste suas montagens antes de migrar totalmente para Stateless Arch, e verifique se quaisquer inconsistências encontradas podem ser resolvidas simplesmente removendo a linha de montagem correspondente no init hook e regerando o init. Por motivos óbvios eu não consigo testar todos os casos de uso imagináveis.

# Live-patch <h4>

Ainda que não plenamente funcional, é possível atualizar o sistema e instalar/desinstalar pacotes sem reinício. E usando btrfs, e um simples hook no pacman, é possível gerar commits bootáveis antes de cada operação. O suporte a live-patch porém é experimental, portanto espere problemas do tipo:
1. Remover um pacote não o remove do path, nem remove seu ícone da área de trabalho imediatamente. As vezes é possível até mesmo seguir executando, caso seja um programa simples sem dependências, mas não confie no pleno funcionamento, espere por inconsistências, não arrisque por exemplo dados sensíveis em um programa nesse estado.  Um reinício corrige essa situação.
2. Instalar um pacote não cria seu respectivo ícone na área de trabalho imediatamente. As vezes é possível executá-lo via terminal, e caso seja um programa gráfico, sua janela talvez se abra, mas não confie no pleno funcionamento, espere por inconsistências, e não arrisque dados sensíveis em um programa nesse estado. Um reinício corrige tudo isso, gerando o ícone e todo o resto.
3. Os dois pontos acima são verdadeiros para atualização do sistema.

**Ou seja, ainda que não totalmente necessário, leve como regra que, ao alterar PacmanRoot, reinicie. Não haverá telas de loading como em outros sistema por aí, a operação já ocorreu, só seu estado precisa ser fixado**

# Implementação <h5>

implementar Stateless Arch em uma instalação nova é simples como:

* pacstrap -c em um único subvolume btrfs (/boot incluso). Deve constar nos pacotes, arch-install-scripts grub grub-btrfs bash e git (-c para não incluir na base a cache do pacstrap);
* arch-chroot no subvolume;
* passwd;
* gerar locales;
* git clone desse repositório(pode ser em /tmp);
* executar o scritp install-stateless-arch-tools.sh
* seguir as instruções finais do scritp (somente operações normais em qualquer instalação do ArchLinux)
* reiniciar

(é possível implementar numa instalação existente, mas os passos necessários mudam conforme o ponto de partida; deixo para você a tarefa de descobrir quais passos são esses :wink:)

# Usabilidade <h6>

Para usar um ArchLinux com Stateless Arch, o sysadmin deve aceitar e conviver com algumas limitações e mudanças de usabilidade:

* atualização e remoção de pacotes somente de forma mediada por pac-base, não diretamento pelo pacman(discutido a seguir). 

* como já deu para perceber, grub como bootloader é uma exigencia aqui. Faço isso para poder incluir o próprio kernel nos commits. Dado que a grub consegue lidar com kernel e initrd sob btrfs, comprimido ou não, seja em legacy ou em efi, se torna uma ferramenta com um fator social e até mesmo ambiental importante : hardware sem capacidade de boot efi continua sendo suportado, e ao ter toda a raiz inclusa em commits, a recuperação de uma atualização problemática, ou mesmo um reset total não passa por mais carga de acesso aos repositórios para baixar iso e pacotes. Mesmo implementar o ArchLinux em outra máquina se torna fácil como um btrfs send via ssh de seu último commit, com a certeza que isso não incluirá chaves ssh,configurações de sysadmins e grupos, pontos de acesso wifi, ou outras configurações sensíveis. O sistema está sempre em "estado de pacstrap", ou muito perto disso. 

* a geração de locale-gen deve ser incluída diretamente na raiz, o que pode ser inconveniente caso o sysadmin troque constantemente de idioma; editar a raiz diretamente será discutido a seguir. Uma alternativa pode ser, durante a instalação do sistema, antes de implementar Stateless Arch, descomentar todos os locales em /etc/locale.gen, e gerar todos.

* devido o estado experimental do live-patch, se valer primariamente de flatpak, appimage, ou, minha alternativa preferida, o excelente Distrobox de 89luca89. Dado que tanto /var quando a home do usuario são separados (ver considerações na sessão sobre montagens), voltar commits da raiz não implica em perder acesso a nenhum desses programas. Delegue á base somente o suficiente para subir o modo gráfico, drivers em geral, suporte a hardware, virtualizadores, o suporte a containers,e outras ferrramentas que dependam de alto nivel de acesso, como por exemplo particionadores de disco.  Mesmo programas de edição de som são plenamente usáveis de dentro de um container (testado usando pipewire e wireplumber). O próprio DistroBox pode ser instalado na home de usuário. Os ícones de desktop de flatpaks, appimages e exportados via Distrobox surgem normalmente em sua área de trabalho, o funcionamento é totalmente transparente. E com distrobox é possível usar pacotes de outras distribuições, não somente do ArchLinux (eu tenho a leve impressão que a maior parte dos sysadmins de Stateless Arch usará Alpine como imagem padrão do Distrobox sempre que possível).

# Manutenção <h7>

Os scripts base-manager, pac-base e commit-root serão salvos em /usr/local/sbin, de forma que uma edição do sysadmin em seu próprio overlay valerá para alterar quaisquer parâmetros que queira. **Isso NÃO é verdadeiro para o hook do init.**

Base-manager acumula cinco funções, uma delas foi citada acima, as demais serão discutidas brevemente abaixo; veja em detalhes clonando esse repositório, e executando base-manager --help

Atualizações e manuseio de programas **(leve em conta a sessão live-patch**) são possíveis usando pac-base, seguido da cli normal do pacman. Pac-base montará PacmanRoot diretamente, por cima dele uma montagem bind de /var/cache/pacman/pkg, /etc/mkinitcpio.conf, /etc/pacman.d, /etc/pacman.conf, /etc/default/grub, /etc/grub.d, /usr/local do sysadmin, e em seguida, provido por arch-install-scripts, executará "arch-chroot pacman" exportando os comandos passados para pac-base. Em /etc/pacman.d/hooks havera um hook pre operação, que apontara para o script commit-root. Como diz o nome, esse script será responsável por gerar um commit do root via snapshot btrfs antes da operação, e atualizar o grub.cfg. O excelente grub-btrfs de Antynea se encarregará de popular o menu de boot com os commits, para os quais se pode recorrer em caso de emergência. 

A atualização do grub.cfg é possivel a partir de base-manager --bootloader-update, e não diretamente pelo grub-mkconfig. Edite /etc/default/grub normalmente em seu overlay, invoque base-manager, e ele cuidará do resto, criando antes um commit. 

Todos os scripts foram escritos com foco em facilitar a leitura e a edição, qualquer comportamento pode ser alterado facilmente, com o sysadmin fazendo isso em seu próprio overlay, e as montagens bind de pac-base se encarregarão de fazer com que o pacman em PacmanRoot as use. Commit-root pode ser trocado por qualquer alternativa que funcione em ambiente chroot. Snapper + snap-pac e  Timershift + timeshift-autosnap não foram testados. 

Caso use commit-root, será papel do sysadmin implementar quaisquer políticas que queira de garbage collector dos commits. No meu uso pessoal, um temporizador systemd roda um script bash a cada 15 dias, e deixa os 20 commits mais recentes. Outra possibilidade é incluir o garbage collector diretamente no hook do pacman, de forma que o número de commits permaneça sempre o mesmo, descartando o commit mais antigo antes de gerar um novo. Ambos os exemplos estão inclusos no repositório, e serão copiados para PacmanRoot durante a implementação, mas não serão habilitados por padrão; Snapper e Timeshift (que repito, NÃO foram testados) possuem cada um suas próprias formas de configurar isso. 

Base-manager --restore-root provê uma forma simples de tornar qualquer dos commits disponíveis em nova PacmanRoot a partir do boot seguinte; não é uma operação destrutiva, e pode ser usado tanto a partir do boot normal, quanto a partir do boot de um dos commits. Só deve ser usado se seus commits forem gerados por commit-root; se usou outra ferramenta para gerar os commits, confie nela também para a restauração.

Com base-manager --edit-pacmanroot, PacmanRoot será montada, e plenamente acessível e manuseável conforme o sysadmin desejar. Os mesmos overlays de pac-base serão montados aqui também. Um commit será gerado antes, portanto aguarde a atualização do bootloader. Para manter a consistência do sistema, evite ao máximo fazer uso disso.

Para editar PacmanRoot sem nenhum overlay, reinicie o sistema, aperte c na tela de boot, e edite a linha do kernel, adicionando ao final "disablehooks=stateless-mode-boot" (sem aspas), e aperte F10. Tenha em mente que, caso use o pacman nessa situação, se a cache não for limpa, dali por diante ela será propagada em todos os commits, assim como quaisquer modificações.

# Considerações finais <h8>

Um leitor atento já percebeu que a ideia aqui é que PacmanRoot permaneça sempre em "estado de pacstrap": Qualquer commit da base terá somente pacotes do pacman, em seus padrões, somado à pouca configuração (senha root e locales) de /etc geradas durante a instalação; faça todo o resto no overlay do sysadmin, e na sua home, e você poderá enviar um commit de PacmanRoot para outra pessoa/dispositivo ( usando btrfs send/receive, tar, rsycn, ou que for), com a certeza de não enviar junto chaves ssh, senhas de wifi, ou outras informações sensíveis; use base-manager --reset-sysadmin-data, e no boot seguinte o sistema retornará em "modo de fábrica".

O sistema dessa forma será altamente resiliente. De fato, excetuando algo que afete diretamente o sistema de arquivos, ou apagar as imagens da grub (mbr do disco se disco mbr+legacy, partição biosboot se gpt+legacy, arquivos da partição fat-32 se efi), o sistema é facilmente recuperável em praticamente qualquer situação sem necessidade de live-boot. Novo kernel/driver de vídeo problemático? Use base-manager --restore-root em um commit anterior. A grub não encontrou o arquivo de   configuração e caiu no shell? Use a cli para chamar o configfile de qualquer um dos commits, todos eles terão um grub.cfg. Grub-rescue? Chame o binário da grub de qualquer um dos commits, e você terá o grub-shell completo, se onde será possível chamar o grub.cfg de qualquer um dos commits.

Caso o sysadmin regrida para um commit onde não exista um determinado binário, mas em seu /etc overlay exista uma configuração de serviço que aponte para esse binário, é possível que o boot seja parado. Isso não implica em um commit de PacmanRoot quebrado, somente em uma configuração de serviço so sysadmin que não pode ser honrada. Esse gerenciamento é totalmente delegado ao sysadmin. Em alguns casos, o shell de emergência do boot pode bastar para remover a inconsistência encontrada e permitir que o boot prossiga. De toda forma, ao regredir commits, cuide para que no commit de destino estejam todos os binários para os quais seus serviços apontam, ou apague esses serviços de seu overlay. Passar "disablehooks=stateless-mode-boot" na linha de comando do kernel iniciará o sistema diretamente em PacmanRoot, com plenas permissões. O sysadmin deve então montar seu overlay manualmente, e inspecionar seus serviços, montagens e configurações em busca do problema que porventura impediram o sucesso do boot. Essa opção deve ser usada APÓS tentativas malsucedidas de boot normal (com Stateless Arch) em commits do root. Caso seja impossível estabelecer qual a causa verdadeira do problema rapidamente, o sysadmin pode simplesmente usar base-manager --reset-sysadmin-data, que irá mover o overlay de dados do sysadmin para um commit, e gerar um novo; o hook no init se encarregará de criar as pastas necessárias, e o sistema iniciara no estado da base, ou de commit escolhido, pronto para novas modificações. O overlay de sysadmin anterior poderá então ser depurado com calma, ou deletado caso o sysadmin estabeleça que não consegue/não vale a pena eliminar todos os problemas encontrados. Essa deve ser uma situação raríssima, mas possível, portanto deve constar nessa documentação. Lembre que, se os commits de PacmanRoot forem read-only (é o padrão de commit-root), não será possível iniciar o sistema neles sem Stateless Arch. Use essa opção diretamente em PacmanRoot. 

Assim como no Suse MicroOS, e em qualquer sistema desse tipo, o sistema não é à prova de um sysadmin com nível de acesso root verdadeiro (e não de dentro de um container) que QUEIRA quebrar o sistema. Exemplos simples: troque o nome do subvolume root no Suse MicroOS, e reinicie, e o boot parará no init. Apague a configuração de boot do Clear Linux, e algo parecido ocorrerá. Apague grub.cfg do Fedora Silverblue, e se depare com grub-shell. Em qualquer que seja o sistema, um dd de dev/zero sobre o root o destrói, obviamente. Portanto, não se trata de desafiar o sysadmin a conseguir quebrar uma instalação, e sim de dificultar ao máximo que um sysadmin que quer MANTER uma instalação funcional a perca, e auxiliá-lo a replicar a instalação se necessário.

O uso de Stateles Arch da forma em que está nesse momento já é possível , mas se trata de uma ferramenta beta. Mesmo quando for terminada, **NÃO SERÁ** indicada para usuários inexperientes. Problemas que exijam conhecimento de pontos de montagem, manipulação do processo de boot e de subvolumes btrfs podem surgir.

**Podem haver problemas e incompatibilidades que eu não encontrei nos meus testes, e que podem aparecer somente com o uso de determinados programas, ou combinação de programas, ou cenários especiais.**

**A máquina é sua, o sistema de arquivos é seu, a decisão de usar esses scripts foi sua, portanto os riscos e prejuízos são seus.**

**O suporte a luks e a secure-boot não foi testado.**
