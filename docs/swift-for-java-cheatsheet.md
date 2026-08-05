# Swift for Java 开发者 · 速查表

> 给有 Java/Spring 底子、刚接触 Swift 的人。**只覆盖 bili-music 里真实出现的语法**,左边 Java、右边 Swift,配本仓库真实代码。
> 卡哪查哪,不用从头读。

---

## 0. 心智地图(先记这三条)

1. **值类型当道**:Swift 的 `struct` 是**值语义**（像 Java `record`，赋值或传参后逻辑上彼此独立），`class` 才是引用语义。编译器和标准库会用优化或 copy-on-write 避免不必要的整份内存复制。bili-music 里 `Track` 是 struct，`PlayerEngine` 是 class。
2. **没有 null,只有 Optional**:可能为空的值类型后面带 `?`,用之前必须"拆包"。这是和 Java 最大的体感差异。
3. **声明式 UI**:SwiftUI 不是"new 一个按钮再 setText",而是"描述界面长什么样,状态变了自动重画"。和 Java Swing/Android 命令式完全两套。

---

## 1. 变量 / 常量 / 类型推断

| Java | Swift |
|---|---|
| `final int x = 1;` | `let x = 1`（常量，优先用） |
| `int x = 1;` | `var x = 1`（变量） |
| `final String s = "a";` | `let s = "a"`（类型自动推断为 String） |
| 显式类型 `List<Track> q` | `var queue: [Track] = []`（类型写在**冒号后**） |

- 能用 `let` 就别用 `var`（编译器会提示）。
- 类型写在变量名**后面**:`name: Type`。

---

## 2. Optional（⭐ 最重要）

Java 用 `null` + 偶尔 `Optional<T>`;Swift 把"可能没有"做进了类型系统。

```swift
var cid: Int?            // 可能有 Int，也可能没有（≈ Integer 可为 null）
let title: String        // 一定有，不可能为 nil
```

**怎么"拆包"用它**:

| 写法 | 含义 | Java 类比 |
|---|---|---|
| `if let cid = track.cid { … }` | 有值才进块，块内 `cid` 是非空 Int | `if (x != null) { … }` |
| `guard let page = info.pages.first else { return }` | 没值就提前 return/throw，**有值则继续往下用** | 卫语句 + 非空 |
| `track.cid ?? 0` | 空合并:为 nil 就取 0 | `Optional.orElse(0)` |
| `current?.bvid` | 可选链:current 为 nil 整个表达式就是 nil | `obj == null ? null : obj.getBvid()` |
| `track.cid!` | **强制拆包**:断定非空，错了直接崩 | 不推荐，等于自找 NPE |

真实例子（[PlayerEngine.swift](../BiliMusic/Player/PlayerEngine.swift)）:
```swift
guard let page = info.pages.first else {
    throw BiliClient.APIError(code: -1, message: "无分P")
}
return (cid ?? page.cid, duration > 0 ? duration : page.duration)
```

> 经验:看到 `?` 就想"这玩意可能没有";看到 `guard let … else` 就读成"拿不到就走人"。

---

## 3. struct vs class（值 vs 引用）

```swift
struct Track: Identifiable, Equatable, Codable { … }   // 值类型，复制
@Observable final class PlayerEngine { … }              // 引用类型，共享
```

| | Java | Swift |
|---|---|---|
| 普通数据对象 | `record Track(...)` / class | `struct`（值语义；底层复制可以被优化） |
| 有身份、要共享的 | class | `class` |

- `Track` 是 struct：把它放进数组或传给函数后，语义上得到独立值，修改局部值不会影响原值；这不等于运行时每次都立即复制整块内存。
- `PlayerEngine` 是 class:全 App 共用**同一个**实例(单一数据源)。
- `final` ≈ Java `final class`(不可被继承)。

---

## 4. 函数 & 参数标签

```swift
func play(tracks: [Track], startAt index: Int, queueMode: QueueMode? = nil) async { … }
```

调用:
```swift
await engine.play(tracks: results, startAt: 0)        // 注意要带参数名
```

| 特性 | Java | Swift |
|---|---|---|
| 参数名 | 调用时不写 | 调用时**默认要写**:`startAt: 0` |
| 外部名/内部名 | 无 | `startAt index`：外部叫 `startAt`，函数内叫 `index` |
| 默认值 | 重载 | `queueMode: QueueMode? = nil` 直接给默认 |
| 异步 | `CompletableFuture` | `async` + 调用处 `await` |

---

## 5. 闭包 / 尾随闭包（Lambda）

| Java | Swift |
|---|---|
| `list.stream().filter(t -> t.ok())` | `list.filter { $0.ok() }` |
| `x -> x.getBvid()` | `{ $0.bvid }`（`$0` = 第一个参数） |
| `Track::getBvid`（方法引用） | `\.bvid`（KeyPath） |

**尾随闭包**:闭包是最后一个参数时,可以挪到括号外:
```swift
Task { await engine.playNext() }          // Task(operation: { … }) 的简写
tracks.map { Track(search: $0) }
tracks.sorted { $0.title < $1.title }
```
真实例子（[SearchStore.swift](../BiliMusic/Features/Search/SearchStore.swift)）:
```swift
.filter { !excluded.contains($0.bvid) }
.filter { MusicFilter.isSearchResult($0, query: query, mode: mode) }
```

---

## 6. 集合 & 高阶函数

| Java | Swift |
|---|---|
| `List<Track>` | `[Track]` |
| `Set<String>` | `Set<String>` |
| `Map<String, Int>` | `[String: Int]` |
| `.stream().map(...)` | `.map { … }`（不用 `.stream()`） |
| `.findFirst()` | `.first(where:) { … }` |
| `.limit(5)` | `.prefix(5)` |
| `.collect(toList())` | 不需要，`map/filter` 直接返回数组 |

---

## 7. 协议（protocol）& 扩展（extension）

- `protocol` ≈ Java `interface`（可带默认实现）。
- `Track: Identifiable, Equatable, Codable` ≈ `class Track implements …`。这几个是系统协议:
  - `Identifiable`：有 `id`，给列表用
  - `Equatable`：能 `==` 比较
  - `Codable`：能 JSON 序列化/反序列化（≈ Jackson，但内建、自动）
- `extension`：给**已存在**的类型加方法（Java 没有；像 Kotlin 扩展函数）:
```swift
private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage { … }   // 给系统 UIImage 加方法
}
```

---

## 8. 枚举（带关联值）& switch

Swift 的 `enum` 比 Java 强很多,能带数据(像 sealed class / record):
```swift
enum State: Equatable {
    case idle, loading, playing, paused
    case failed(String)        // 这个 case 还能装一条错误信息
}
```
用 `switch` 解构(必须**穷尽**所有 case,否则编译不过):
```swift
switch player.timeControlStatus {
case .playing:  self.state = .playing
case .paused:   if self.state == .playing { self.state = .paused }
case .waitingToPlayAtSpecifiedRate: self.state = .loading
@unknown default: break
}
```
取关联值:`if case .failed(let message) = engine.state { … }`

---

## 9. 并发：async / await / Task / actor / @MainActor

| 概念 | Java 类比 | Swift |
|---|---|---|
| 异步函数 | 返回 `CompletableFuture` | `func foo() async throws -> T` |
| 调用异步 | `.get()` / `thenApply` | `try await foo()` |
| 起一个异步任务 | `executor.submit(...)` | `Task { await … }` |
| 必须在 UI 线程 | `SwingUtilities.invokeLater` | `@MainActor`（标在类/方法上，自动调度到主线程） |
| 线程安全对象 | `synchronized` / 锁 | `actor`（内部访问自动串行化，免手写锁） |
| 并行跑一批再汇总 | `CompletableFuture.allOf` / parallelStream | `withTaskGroup { … }` |

真实例子（[RecommendationEngine.swift](../BiliMusic/Player/RecommendationEngine.swift)）——并行请求多个种子的相关推荐再汇总:
```swift
await withTaskGroup(of: [Candidate].self) { group in
    for seed in seeds {
        group.addTask { … }          // 每个 seed 一个并行任务
    }
    var candidates: [Candidate] = []
    for await batch in group {       // 收集各任务结果
        candidates.append(contentsOf: batch)
    }
    return candidates
}
```
- `@MainActor` 标在 `PlayerEngine` 上 = "这个类所有方法默认跑主线程",UI 状态改起来安全。
- `actor`（如 `ImageLoadCoordinator`）= 多个任务同时访问也不会数据竞争。

---

## 10. 错误处理

| Java | Swift |
|---|---|
| `throws IOException`（受检异常） | `func f() throws -> T` |
| `try { … } catch (e) { … }` | `do { try … } catch { … }` |
| 吞掉异常返回 null | `try?`（失败就返回 nil，不抛） |
| `throw new XxxException()` | `throw SomeError(...)` |

```swift
let online = try? await lyricsClient.lyrics(for: track)   // 失败就 online = nil
do {
    folders = try await BiliClient().favFolders()
} catch {
    errorMessage = error.localizedDescription              // error 是隐式变量名
}
```

---

## 11. 杂项语法糖

| 场景 | Java | Swift |
|---|---|---|
| 字符串拼接 | `"hi " + name` / `String.format` | `"hi \(name)"`（插值） |
| 三元 | `a ? b : c` | 一样 `a ? b : c` |
| 区间 | `IntStream.range(0,5)` | `0..<5`（不含 5）、`0...5`（含 5） |
| 类型判断+转换 | `if (x instanceof Foo f)` | `if let f = x as? Foo` |
| 静态成员 | `Foo.BAR` | `Foo.bar`（一样，注意小驼峰） |
| 只读属性 | `private final` + getter | `private(set) var` |
| 计算属性（getter） | `int getX(){return a+b;}` | `var x: Int { a + b }` |

---

## 12. Property Wrapper（注解似的修饰符，Java 无对应）

SwiftUI 里这些 `@` 开头的不是普通注解,它们会**改写字段的存取行为**:

| 修饰符 | 作用（粗略类比） |
|---|---|
| `@Observable` | 标在 class 上，其属性变化能驱动 UI 重画（≈ 可观察 Bean） |
| `@State` | View 自己持有的局部状态 |
| `@Environment(PlayerEngine.self)` | 依赖注入读全局对象（≈ `@Autowired` 拿单例） |
| `@AppStorage("autoCache")` | 直接读写 UserDefaults（≈ 绑定到配置项的字段） |
| `@Binding` | 双向绑定，子 View 能改父 View 的状态 |

真实例子（[SettingsView.swift](../BiliMusic/Features/Settings/SettingsView.swift)）:
```swift
@AppStorage("playbackQuality") private var playbackQuality = 0   // 改它=改 UserDefaults
@State private var showLogin = false
@Environment(PlayerEngine.self) private var engine              // 拿全局播放器
```

---

## 13. SwiftUI 一瞥（这块单独再开一课）

```swift
struct HomeView: View {          // 一个界面 = 一个 struct，实现 View 协议
    var body: some View {        // body 描述"长什么样"
        List { … }               // 声明式：列出有什么，不写"怎么画"
    }
}
```
- `some View` ≈ "返回某个具体的 View 类型,编译器自己推断"。
- 没有 `setText/addView`;**状态变 → SwiftUI 自动重算 body 重画**。
- 这块和后端思维差最远,建议拿一个真实 View 单独精讲。

---

## 用法建议

- 把这份和代码并排开。读到不认识的符号,回这里查那一节。
- 读代码顺序推荐:`CookieStore.swift`(最短) → `SettingsView.swift` → `SearchView.swift` → `PlayerEngine.swift`(最硬)。
- 看不懂的写法,直接问我"这行 Swift 等于 Java 什么",我按你的代码讲。
