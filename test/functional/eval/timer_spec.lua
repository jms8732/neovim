local helpers = require('test.functional.helpers')(after_each)
local Screen = require('test.functional.ui.screen')
local ok, feed, eq, eval = helpers.ok, helpers.feed, helpers.eq, helpers.eval
local source, nvim_async, run = helpers.source, helpers.nvim_async, helpers.run
local clear, execute, funcs = helpers.clear, helpers.execute, helpers.funcs
local curbufmeths = helpers.curbufmeths

describe('timers', function()
  before_each(function()
    clear()
    source([[
      let g:val = 0
      func MyHandler(timer)
        let g:val += 1
      endfunc
    ]])
  end)

  it('works one-shot', function()
    execute("call timer_start(50, 'MyHandler')")
    eq(0,eval("g:val"))
    run(nil, nil, nil, 200)
    eq(1,eval("g:val"))
  end)

  it('works one-shot when repeat=0', function()
    execute("call timer_start(50, 'MyHandler', {'repeat': 0})")
    eq(0,eval("g:val"))
    run(nil, nil, nil, 200)
    eq(1,eval("g:val"))
  end)


  it('works with repeat two', function()
    execute("call timer_start(50, 'MyHandler', {'repeat': 2})")
    eq(0,eval("g:val"))
    run(nil, nil, nil, 300)
    eq(2,eval("g:val"))
  end)

  it('are triggered during sleep', function()
    execute("call timer_start(50, 'MyHandler', {'repeat': 2})")
    nvim_async("command", "sleep 10")
    eq(0,eval("g:val"))
    run(nil, nil, nil, 300)
    eq(2,eval("g:val"))
  end)

  it('works with zero timeout', function()
    -- timer_start does still not invoke the callback immediately
    eq(0,eval("[timer_start(0, 'MyHandler', {'repeat': 1000}), g:val][1]"))
    run(nil, nil, nil, 400)
    eq(1000,eval("g:val"))
  end)

  it('can be started during sleep', function()
    nvim_async("command", "sleep 10")
    -- this also tests that remote requests works during sleep
    eval("timer_start(50, 'MyHandler', {'repeat': 2})")
    eq(0,eval("g:val"))
    run(nil, nil, nil, 300)
    eq(2,eval("g:val"))
  end)

  it('are paused when event processing is disabled', function()
    execute("call timer_start(50, 'MyHandler', {'repeat': -1})")
    run(nil, nil, nil, 100)
    local count = eval("g:val")
    -- shows two line error message and thus invokes the return prompt.
    -- if we start to allow event processing here, we need to change this test.
    execute("throw 'fatal error'")
    run(nil, nil, nil, 300)
    feed("<cr>")
    local diff = eval("g:val") - count
    ok(0 <= diff and diff <= 4)
  end)

  it('are triggered in blocking getchar() call', function()
    execute("call timer_start(50, 'MyHandler', {'repeat': -1})")
    nvim_async("command", "let g:c = getchar()")
    run(nil, nil, nil, 300)
    feed("c")
    local count = eval("g:val")
    ok(count >= 4)
    eq(99, eval("g:c"))
  end)

  it('can invoke redraw in blocking getchar() call', function()
    local screen = Screen.new(40, 6)
    screen:attach()
    screen:set_default_attr_ids({
        [1] = {bold=true, foreground=Screen.colors.Blue},
    })

    curbufmeths.set_lines(0, -1, true, {"ITEM 1", "ITEM 2"})
    source([[
      func! AddItem(timer)
        call nvim_buf_set_lines(0, 2, 2, v:true, ['ITEM 3'])
        redraw
      endfunc
      call timer_start(200, 'AddItem')
    ]])
    nvim_async("command", "let g:c2 = getchar()")

    screen:expect([[
      ITEM 1                                  |
      ITEM 2                                  |
      {1:~                                       }|
      {1:~                                       }|
      {1:~                                       }|
      ^                                        |
    ]])

    screen:sleep(200)
    screen:expect([[
      ITEM 1                                  |
      ITEM 2                                  |
      ITEM 3                                  |
      {1:~                                       }|
      {1:~                                       }|
      ^                                        |
    ]])

    feed("3")
    eq(51, eval("g:c2"))
    screen:expect([[
      ^ITEM 1                                  |
      ITEM 2                                  |
      ITEM 3                                  |
      {1:~                                       }|
      {1:~                                       }|
                                              |
    ]])
  end)

  it('can be stopped', function()
    local t = eval("timer_start(50, 'MyHandler', {'repeat': -1})")
    eq(0,eval("g:val"))
    run(nil, nil, nil, 300)
    funcs.timer_stop(t)
    local count = eval("g:val")
    run(nil, nil, nil, 300)
    local count2 = eval("g:val")
    ok(4 <= count and count <= 7)
    -- when count is eval:ed after timer_stop this should be non-racy
    eq(count, count2)
  end)

  it('can be stopped from the handler', function()
    source([[
      func! MyHandler(timer)
        let g:val += 1
        if g:val == 3
          call timer_stop(a:timer)
          " check double stop is ignored
          call timer_stop(a:timer)
        endif
      endfunc
    ]])
    execute("call timer_start(50, 'MyHandler', {'repeat': -1})")
    eq(0,eval("g:val"))
    run(nil, nil, nil, 300)
    eq(3,eval("g:val"))
  end)

  it('can have two timers', function()
    source([[
      let g:val2 = 0
      func! MyHandler2(timer)
        let g:val2 += 1
      endfunc
    ]])
    execute("call timer_start(50,  'MyHandler', {'repeat': 3})")
    execute("call timer_start(100, 'MyHandler2', {'repeat': 2})")
    run(nil, nil, nil, 300)
    eq(3,eval("g:val"))
    eq(2,eval("g:val2"))
  end)

  it('do not crash when processing events in the handler', function()
    source([[
      let g:val = 0
      func! MyHandler(timer)
        call timer_stop(a:timer)
        sleep 100m
        let g:val += 1
      endfunc
    ]])
    execute("call timer_start(5, 'MyHandler', {'repeat': 1})")
    run(nil, nil, nil, 300)
    eq(1,eval("g:val"))
  end)


  it("doesn't mess up the cmdline", function()
    local screen = Screen.new(40, 6)
    screen:attach()
    screen:set_default_attr_ids( {[0] = {bold=true, foreground=255}} )
    source([[
      func! MyHandler(timer)
        echo "evil"
      endfunc
    ]])
    execute("call timer_start(100,  'MyHandler', {'repeat': 1})")
    feed(":good")
    screen:sleep(200)
    screen:expect([[
                                              |
      {0:~                                       }|
      {0:~                                       }|
      {0:~                                       }|
      {0:~                                       }|
      :good^                                   |
    ]])
  end)

end)
