#!/bin/sh

#
# nanoKONTROL2.sh
#

# First version: Mon Jul  1 23:33:46 JST 2019
# Last update: Sun Sep  1 00:14:20 JST 2019
# Last update: Mon Sep  2 13:25:13 JST 2019

# amidi のダンプ出力を読み取り，イベント発生時のスライダ、ボリューム、S/M/Rスイッチの状況を出力する

# 通常の行指向のデータは、「data, data, ... data, 改行」であるのに対し，
# amidi のダンプは，「改行, data, data, ... data」となっている．事前に通常の形式にしておく必要がある．

# ----------------------------------------------------------

# Currently 3A and 3B are not used.
# So these keys are tentatively assigned to the same role of the [CYCLE] button.

# ----------------------------------------------------------

awk 'BEGIN {
    vflag = 1;  ## 直近に有効操作があったら 1, なければ 0
    app = 1;    ## 現在の app 番号
    run = 1;    ## 1 なら実行状態，0 ならサスペンド状態

    for(i = 0; i < 8; i++) {
        val0[i] = 0;    ## スライダの値を初期化
        val2[i] = 0;    ## ノブの値を初期化
        for(j = 0; j < 3; j++) {
            SMR[i*3+j] = 0;     ## S / M / R の各ボタンの値を初期化
        }
    }
}

{
    # STDIN から16進数表記の数字を3つ読み取る
    # すでに，通常の形式（行の末尾に改行が来る形式）に変換されているのが前提

    # 3組の数字（それぞれは16進数表記の1バイト（＝2文字））を V1, V2, V3 に読み込む
    v1 = $1;
    v2 = $2;
    v3 = $3;
    v12 = $1 $2;        # 最初の2バイト
    v123 = $1 $2 $3;    # 全体（3バイト）

    # nanoKontrol2 の左側のボタン．実際の MIDI 通信では前に B0，後ろに 00 か 7F を伴っている．
    x_list = "3C 3D 3E 2B 2C 2A 29 2D";         ## 3C：SET, 3D：<, 3E：>, 2B：<<, 2C：>>, 2A：□, 29：＞, 2D：◯,
    n_data  = split(x_list, x_array);

    # - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # app 切り替え (本スクリプトでは nanoKontrol2 を最大で同時に8種類の異なる用途で使えるようにしている．この「異なる用途」を app と呼称する）

    for (i = 1; i <= n_data; i++) {
        x = x_array[i];
        v = "B0" x "7F";                        ## v is one of: B03C7F：SET, B03D7F：<, B03E7F：>, B02B7F：<<, B02C7F：>>, B02A7F：□, B0297F：＞, B02D7F：◯
        if (v123 == v) {
            ## app が切り替わった直後は run が 0 になり suspend 状態になる（いきなり新しい app に値が送られ始めるのを防ぐため）
            app = i;    ## app 更新
            run = 0;    ## サスペンド状態
            printf "# app = %d (App%d has been selected but currently suspended. Push [CYCLE] button to resume)\n", app, app;
        }
    }

    # - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # [CYCLE] ボタンが押されたら，当該 app の suspend 状態を解除
    # 切り替え直後は出力を抑止することで，新しい app の望ましい初期値（再開値）に変更する操作を行ってもその値は出力されずにすむ．
    # この機能がないと，app を切り替えた途端に「直前の app」の最後のデータが送られてしまう。


    if ((v123 == "B02E7F") || (v123 == "B03A7F") || (v123 == "B03B7F")) {     ## [CYCLE] and two unused keys have been assigned ([track <] and [track >])
        printf "# app = %d (Go!)\n", app;
        run = 1;        ## 実行状態（サスペンド解除）
    }

    # - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # スライダ

    for (i = 0; i <= 8; i++) {
        x = "B00" i;            ## スライダを表す先頭2バイト：左から右へ B000, B001, B002, ... B007
        if (v12 == x) {
            val0[i] = v3;
            vflag = 1;          ## 直近に有効操作あり
        }
    }

    # - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # ボリューム（ノブ）

    for (i = 0; i <= 7; i++) {
        x = "B01" i;            ## ノブを表す先頭2バイト：左から右へ B100, B101, B102, ... B107
        if (v12 == x) {
            val1[i] = v3;
            vflag = 1;          ## 直近に有効操作あり
        }
    }

    # - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # S / M / R ボタン

    for (i = 0; i <= 7; i++) {          ## Sボタン：左から右へ B020{00,7F}, B021{00,7F}, B022{00,7F}, ... B027{00,7F}
        for (j = 2; j <= 4; j++) {      ## Mボタン：左から右へ B030{00,7F}, B031{00,7F}, B032{00,7F}, ... B037{00,7F}
                                        ## Rボタン：左から右へ B040{00,7F}, B041{00,7F}, B042{00,7F}, ... B047{00,7F}
            x = "B0" j i "7F";          ## x：当該ボタンがオンの場合の値
            y = "B0" j i "00";          ## y：当該ボタンがオフの場合の値
            if (v123 == x) {
                ## オン状態
                ## 同一チャネルの（== 縦方向に並ぶ）S/M/R ボタンを一旦クリアする
                for (k = 2; k <= 4; k++) {
                    SMR[i*3+(k-2)] = 0;
                }
                ## その上で当該ボタンをオンとする
                SMR[i*3+(j-2)] = 1;
                vflag = 1;              ## 直近に有効操作あり
            }
            if (v123 == y) {
                ## オフ状態
                SMR[i*3+(j-2)] = 0;
                vflag = 1;              ## 直近に有効操作あり
            }
        }
    }

    # - - - - - - - - - - - - - - - - - - - - - - - - - - -

    ## 現在実行中（非サスペンド状態）かつ，直前にappが切り替わったか何らかの有効操作が行われた場合
    if ((run == 1) && ((prevApp != app) || (vflag != 0))) {
        prevApp = app;          ## 現在の app を保存
        vflag = 0;              ## 直近に有効操作なし

        ## 現状を出力
        ## （出力形式を変更したい場合は以下を修正すればよい）
        printf "%s:", app;
        for(i = 0; i < 8; i++) {
            printf " %s", strtonum("0x"val0[i]);
        }

        printf " :", app;
        for(i = 0; i < 8; i++) {
            printf " %s", strtonum("0x"val1[i]);
        }

        printf " :", app;
        for(i = 0; i < 8; i++) {
            printf " %d %d %d", SMR[i*3+0], SMR[i*3+1], SMR[i*3+2];
        }
        printf " :", app;

        printf("\n");
        ## fflush();
    }

    # - - - - - - - - - - - - - - - - - - - - - - - - - - -

    fflush();
}'
