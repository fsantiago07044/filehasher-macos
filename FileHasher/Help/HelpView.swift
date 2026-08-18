import SwiftUI

/// The in-app help window: topic sidebar on the left, rendered sections on
/// the right. Content lives in HelpContent so it stays versioned with the app.
struct HelpView: View {
    @State private var selection: HelpTopic? = HelpContent.topics.first

    var body: some View {
        NavigationSplitView {
            List(HelpContent.topics, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.icon).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            if let topic = selection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(topic.title)
                            .font(.title2.bold())
                            .padding(.bottom, 2)

                        ForEach(topic.sections) { section in
                            HelpSectionView(section: section)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Select a topic")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("FileHasher Help")
    }
}

private struct HelpSectionView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let heading = section.heading {
                Text(heading)
                    .font(.headline)
                    .padding(.top, 4)
            }
            ForEach(section.paragraphs, id: \.self) { para in
                Text(inline(para))
            }
            if !section.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.bullets, id: \.self) { bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(inline(bullet))
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    /// Renders inline Markdown (bold, code) and falls back to plain text.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
