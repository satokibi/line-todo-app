class LinebotController < ApplicationController
  require 'line/bot'  # gem 'line-bot-api'


  def initialize
    @help_messages = ['ヘルプ', 'へるぷ', '使い方', 'つかいかた', 'help']
    @register_messages = ['する', '登録', 'do']
    @delete_messages = ['した', '消す', 'やった', '終わった', '削除', 'done']
    @all_delete_messages = ['全部消す', '全て削除', 'すべて削除', '全削除']
  end


  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head :bad_request
    end

    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          user_message = event.message['text']

          # 全角数字を全て半角数字へ
          user_message.tr!("０-９", "0-9")

          # 改行と空白でsplit
          split_message = user_message.gsub(/\n/,' ').split(/[[:blank:]]+/)

          return_message = ''
          case split_message.length
          when 1
            return_message = single_message(event, split_message[0])
          else
            return_message = multi_message(event, split_message)
          end

          message = { type: 'text', text: return_message }
          client.reply_message(event['replyToken'], message)
        end
      end
    }
    head :ok
  end

  private


    # userの入力が空白を含まない１つの文の時の処理
    def single_message(event, user_message)
      case user_message
      when *@help_messages
        return "使い方:\n" +
                "# ToDo登録\n" +
                "登録する文章 + 空白 + する と送る\n" +
                "例1: 付箋買う する\n" +
                "例2: 歯医者行く する\n" +
                "\n" +
                "# ToDo完了\n" +
                "番号 + 空白 + した と送る\n" +
                "例1: 0 した\n" +
                "例2: 1 した\n" +
                "\n" +
                "# ToDo確認\n" +
                "適当なメッセージを送る\n" +
                "例1: あ\n" +
                "例2: あああ\n" +
                "\n" +
                "# その他\n" +
                "## 使い方を見る時\n" +
                "ヘルプ\n" +
                "## タスクを全て削除する\n" +
                "全削除\n"

      when *@all_delete_messages
        return delete_all_todo(event)
      else
        # 入力に@delete_messagesの文字が含まれていたら
        if user_message.delete("0-9").in?(@delete_messages)
          # 入力に含まれる数字の数
          num_count_in_split_message = user_message.scan(/\d+/).length
          logger.debug(num_count_in_split_message)
          if num_count_in_split_message == 0
            logger.debug("num count => 0")
            return "削除するタスクの番号を１つ入れてね\n例: 1 した, 1 削除, 1 やった"
          elsif num_count_in_split_message == 1
            # 入力に含まれる数が１つならその番号のタスクを削除
            logger.debug("num count => 1")
            return delete_todo(event, [user_message.delete("^0-9")])
          else
            logger.debug("num count => else")
            return "1つずつしか削除できないよ(T_T)!"
          end
        else
          todos = Todo.where(user: event['source']['userId'])
          if todos.length == 0
            return '今のタスクはないよ！'
          else
            return "今のタスクだよ\n" + make_todo(todos)
          end
        end
      end
    end

    # userの入力が空白を含む文のときの処理
    def multi_message(event, split_message)
      case split_message[-1]
      when *@register_messages
        return register_todo(event, split_message)
      when *@delete_messages
        return delete_todo(event, split_message)
      else
        todos = Todo.where(user: event['source']['userId'])
        if todos.length == 0
          return '今のタスクはないよ！'
        else
          return "今のタスクだよ\n" + make_todo(todos)
        end
      end
    end

    # 文字列が数字だけで構成されていれば true を返す
    def number?(str)
      # 文字列の先頭(\A)から末尾(\z)までが「0」から「9」の文字か
      nil != (str =~ /\A[0-9]+\z/)
    end

    def make_todo(todos)
      return todos.map.with_index { |todo, index| "#{index}: #{todo.title}" }.join("\n")
    end

    def register_todo(event, sp)
      # 配列最後の"する", "登録"等の文字を取り除く
      sp.pop
      todo = Todo.new(title: sp.join(' '), user: event['source']['userId'])
      if todo.save
        todos = Todo.where(user: event['source']['userId'])
        return "#{todo.title} を登録したよ！\n" + make_todo(todos)
      else
        return '登録失敗しました...'
      end
    end

    def delete_todo(event, sp)
      todos = Todo.where(user: event['source']['userId'])
      if( todos.length == 0 )
        return "今のタスクはないよ！"
      end

      if( sp.length > 2 )
        return "1つずつしか削除できないよ(T_T)!"
      end

      if( !number?(sp[0]) )
        return "数字を入力してね(T_T)"
      end

      user_input_index = sp[0].to_i
      # ユーザの入力が配列の範囲内に入っていない時
      if( !user_input_index.in?(0..todos.length-1) )
        return "0 ~ #{todos.length-1}の間の数字で入力してね(T_T)"
      end

      delete_id = todos[sp[0].to_i].id
      delete_todo = Todo.find(delete_id)
      delete_todo_title = delete_todo.title
      if delete_todo.destroy
        todos = Todo.where(user: event['source']['userId'])
        if todos.length == 0
          return "#{delete_todo_title} を完了したよ。\nお疲れ様！\n残りのタスクはないよ！"
        else
          return "#{delete_todo_title} を完了したよ。\nお疲れ様！\n残りのタスクだよ\n" + make_todo(todos)
        end
      else
        return "削除に失敗しました...(T_T)"
      end
    end

    def delete_all_todo( event )
      todos = Todo.where(user: event['source']['userId'])
      success_flag = true
      delete_todos_title = make_todo(todos)
      todos.each do |todo|
        if !todo.destroy
          success_flag = false
        end
      end
      if success_flag
        return "以下の全てのタスクを削除しました！\n#{delete_todos_title}"
      else
        return "削除に失敗しました...(T_T)"
      end
    end


end
